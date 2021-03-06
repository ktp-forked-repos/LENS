;; Wireless channel for WSN
;; Copyright (C) 2014 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;;; Copying:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; LENS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This channel model accounts for varying interference and path loss.
;; It ignores propagation delay as for WSNs this is much less than
;; one bit duration.

;;; Code:
(in-package :lens.wsn)

(defstruct cell
  "An area of radio coverage with the list
of nodes wthin it and a list of [[path-loss]] records to other
cells."
  (coord (make-coord) :type coord)
  (occupation nil :type list)
  (path-loss nil :type list))

(defstruct path-loss
  "Record of path-loss to another [[cell]]. Includes observation time
information for temporal modelling as well as static /avg-path-loss/."
  (destination nil :type (or cell nil))
  (avg-path-loss 0.0 :type real)
  (last-observed-difference-from-avg 0.0 :type float)
  (last-observation-time (simulation-time) :type time-type))

(register-signal
 'fade-depth
 "Signaled to record temporal changes in signal power")

(defgeneric run-temporal-model(model time signal-variation)
  (:documentation "* Arguments

- model :: a [[temporal-model]] module
- time :: a [[time-type]]
- signal-variation :: a [[real]]

* Description

Given a time interval /time/ since the last estimate and the previous
/signal-variation/ from /model/ return the new /signal-variation/ and
the amount of time processed (i.e. the amount to be take off
/time/)"))

(defgeneric path-loss-signal-variation(model path-loss)
  (:documentation "* Arguments

- model :: a [[temporal-model]] module
- path-loss :: a [[path-loss]] structure

* Description

Given a temporal /model/ and /path-loss/ structure run the temporal
model using [[run-temporal-model]], updating the path-loss structure
and returning the new signal variation.")
  (:method :around (model path-loss)
       (let ((*context* model)) (call-next-method)))
  (:method(model (path-loss path-loss))
    (let* ((time-passed (- (simulation-time)
                           (path-loss-last-observation-time path-loss))))
    (multiple-value-bind(signal-variation time-processed)
        (run-temporal-model
         model
         time-passed
         (path-loss-last-observed-difference-from-avg  path-loss))
      (tracelog "Signal variation(~gdB,~gs)=~g"
                (path-loss-last-observed-difference-from-avg  path-loss)
                time-processed signal-variation)
      (setf (path-loss-last-observed-difference-from-avg path-loss)
            signal-variation)
      (incf (path-loss-last-observation-time path-loss)
            time-processed)
      (emit model 'fade-depth signal-variation)
      signal-variation))))

(defclass wireless-channel(compound-module)
  ((cell-size
    :type coord :parameter t :initform (make-coord 5.0 5.0 1.0)
    :reader cell-size
    :documentation "Size of cells in each dimension (for mobility)")
   (field
    :type coord :reader field
    :documentation "wireless coverage field (may be larger than network field")
   (signal-delivery-threshold
    :parameter t :type real :initform -100.0 :initarg :signal-delivery-threshold
    :accessor signal-delivery-threshold
    :documentation "threshold in dBm above which, wireless channel
    module is delivering signal messages to radio modules of
    individual nodes")
   (temporal-model
    :reader temporal-model
    :documentation "the temporal channel variation model")
   (max-tx-power :type real :initform 0.0 :accessor max-tx-power)
   (receivers
    :type array :reader receivers
    :documentation "an array of lists of receiver gateways affected by
    ongoing transmission.")
   (cells
    :type array :reader cells
    :documentation "an array of cell entities with node occupation and
    path-loss to other cells")
   (location-cells :type hash-table :initform (make-hash-table)
                   :documentation "Cached location cell by node instance"))
  (:default-initargs :num-rngs 3)
  (:gates
   (fromNodes :input))
  (:submodules
   (temporal-model no-temporal-model)
   (path-loss-model log-distance))
  (:properties
   :statistic (fade-depth
               :title "Fade Depth"
               :default ((histogram :min -50.0 :max 15.0 :num-cells 14
                                    :units "dB" :format "~0@/dfv:eng/"))))
  (:metaclass compound-module-class)
  (:documentation "The wireless channel module simulates the wireless
  medium. Nodes sent packets to it and according to various
  conditions (fading, interference etc) it is decided which nodes can
  receive this packet."))

(defmethod build-submodules :after ((instance wireless-channel))
    (setf (slot-value instance 'temporal-model)
          (submodule instance 'temporal-model)))

(defun coord-cell(coord module)
  "Return row major aref  of cell indicies corresponding to coord for wireless
channel module"
  (let ((cells (cells module)))
    (row-major-aref
     cells
     (apply #'array-row-major-index
            cells
            (mapcar
             #'(lambda(f)
                 (let* ((coord (funcall f coord))
                        (field (funcall f (field module)))
                        (a (max 0 (min coord field))))
                   (when (> coord field)
                     (tracelog "Warning at initialization: node position out of bounds in ~A dimension!" f))
                   (floor a (funcall f (cell-size module)))))
             (load-time-value (list #'coord-x #'coord-y #'coord-z)))))))

(defun location-cell(channel instance)
  (or (gethash instance (slot-value channel 'location-cells))
      (index (node instance))))

(defun (setf location-cell)(index channel instance)
  (setf (gethash instance (slot-value channel 'location-cells)) index))

(defun map-array(f a)
  "Map function f over array a returning list of return values"
  (let ((result nil))
    (dotimes(i (array-total-size a))
      (push (funcall f (row-major-aref a i)) result))
    (nreverse result)))

(defmethod initialize list ((wireless wireless-channel) &optional (stage 0))
  (let* ((nodes (nodes (network *simulation*))))
    (case stage
      (0
       (map 'nil #'(lambda(node) (subscribe node 'node-move wireless)) nodes)
       (setf (slot-value wireless 'receivers)
             (make-array (length nodes)
                         :element-type 'list
                         :initial-element nil))
       nil)
      (1
       (if (every #'(lambda(node) (static-p (submodule node 'mobility)))
                  nodes)
           (progn  ;; all static then one node per cell
             (setf (slot-value wireless 'cells) (make-array (length nodes)))
             (map 'nil
                  #'(lambda(node)
                      (let ((idx (index node)))
                        (setf (location-cell wireless node)
                              (setf (aref (cells wireless) idx)
                                    (make-cell :coord (location node)
                                               :occupation (list node))))))
                  nodes))
           (with-slots(field cell-size cells) wireless
             (setf field
                   (coord-op #'(lambda(f) (if (<= f 0.0) 1.0 f))
                          (field (network wireless))))
             (setf cell-size
                   (coord-op #'(lambda(f c)  (if (<= c 0.0) f (min f c)))
                             field cell-size))
             (let ((dimensions
                    (let ((d (coord-op #'/ field cell-size)))
                      (mapcar #'ceiling
                              (list (coord-x d) (coord-y d) (coord-z d))))))
               (setf (slot-value wireless 'cells) (make-array dimensions))
               (dotimes(i (first dimensions))
                 (let ((x (* i (coord-x cell-size))))
                   (dotimes(j (second dimensions))
                     (let ((y (* j (coord-y cell-size))))
                       (dotimes(k (third dimensions))
                         (let ((z (* k (coord-z cell-size))))
                           (setf (aref cells i j k)
                                 (make-cell
                                  :coord (make-coord x y z))))))))))
               (map 'nil
                    #'(lambda(node)
                        (let ((cell (coord-cell (location node) wireless)))
                          (setf (location-cell wireless node) cell)
                          (push node (cell-occupation cell))))
                    nodes)))
       nil)
      (2
       (let* ((cells (cells wireless))
             (no-cells (array-total-size cells)))
         (tracelog "Number of space cells: ~A" no-cells)
         (tracelog "Each cell affects ~A other cells on average."
                   (/ (reduce #'+
                              (map-array
                               #'(lambda(cell) (length  (cell-path-loss cell)))
                               cells))
                      no-cells)))
       t))))

(defclass wireless-signal-start(message)
  ((src :initarg :src :reader src
       :documentation "Source ID for this signal")
   (power-dBm :type real :initarg :power-dBm :accessor power-dBm
              :documentation "Power level of the signal at recever.")
   (carrier-frequency :type real :initarg :carrier-frequency
                      :reader carrier-frequency)
   (bandwidth :type real :initarg :bandwidth :reader bandwidth)
   (modulation :initarg :modulation :reader modulation
               :documentation "Modulation format of signal")
   (encoding :initarg :encoding :reader encoding
             :documentation "Encoding of signal"))
  (:documentation "Message used to record the start of reception of a
  radio signal at one [[cell]] from another. Data is encapsulated in
  [[wireless-end]] packet"))

(defmethod print-object((msg wireless-signal-start) os)
  (print-unreadable-object(msg os :type t :identity nil)
    (format os "~5,2fdBm from ~A" (power-dbm msg)  (nodeid (node (src msg))))))

(defmethod duplicate((original wireless-signal-start) &optional
                     (duplicate (make-instance 'wireless-signal-start)))
  (call-next-method)
  (copy-slots
   '(src power-dbm carrier-frequency bandwidth modulation encoding)
   original duplicate))

(defclass wireless-signal-end(packet)
  ((src :initarg :src :reader src
        :documentation "Source ID must match signal start source id")
   (header-overhead :type integer :initform 0 :reader header-overhead
                    :initarg :header-overhead))
  (:documentation "Packet message used to record end of the
  transmission of a signal from one [[cell]] to another. Encapsulates
  the transmitted data packet. [[header-overhead]] is the physical
  layer overhead in byte-lengths e.g. for framing etc."))

(defmethod byte-length((pkt wireless-signal-end))
  (+ (header-overhead pkt)
     (byte-length (slot-value pkt 'lens::encapsulated-packet))))

(defmethod bit-length((pkt wireless-signal-end))
  (* 8 (byte-length pkt)))

(defmethod print-object((msg wireless-signal-end) os)
  (print-unreadable-object(msg os :type t :identity nil)
    (format os "from ~A"  (nodeid (node (src msg))))))

(defmethod duplicate((original wireless-signal-end) &optional
                     (duplicate (make-instance 'wireless-signal-end)))
  (call-next-method)
  (copy-slots '(src) original duplicate))

(defmethod receive-signal((wireless wireless-channel) (signal (eql 'node-move))
                          (mobility mobility) value)
  (declare (ignore value))
  (let* ((node (node mobility))
         (old-cell (location-cell wireless node))
         (new-cell (coord-cell (location mobility) wireless)))
    (unless (eql old-cell new-cell)
      (setf (cell-occupation old-cell)
            (delete node (cell-occupation old-cell)))
      (push node (cell-occupation new-cell))
      (setf (location-cell wireless (node mobility)) new-cell))))

(defmethod handle-message((wireless wireless-channel)
                          (message wireless-signal-start))
  (let* ((src-node (node (src message)))
         (cell-tx (location-cell wireless src-node))
         (nodeid (nodeid src-node))
         (reception-count 0))
    (dolist(path-loss (cell-path-loss cell-tx))
      (when (cell-occupation (path-loss-destination path-loss))
        (let ((current-signal-received
               (+
                (- (power-dbm message) (path-loss-avg-path-loss path-loss))
                (path-loss-signal-variation
                 (temporal-model wireless) path-loss))))
          (unless (< current-signal-received
                     (signal-delivery-threshold wireless))
            ;; go through all nodes in that cell and send copy of message

            (dolist(node (cell-occupation (path-loss-destination path-loss)))
              (unless (eql node src-node)
                (incf reception-count)
                (let ((msgcopy (duplicate message))
                      (receiver (gate node 'receive :direction :input)))
                  (setf (power-dbm msgcopy) current-signal-received)
                  (send-direct wireless receiver msgcopy)
                  (push receiver (aref (receivers wireless) nodeid)))))))))
    (when reception-count
      (tracelog "Signal from ~A reached ~D other nodes."
                src-node reception-count))))

(defmethod handle-message((wireless wireless-channel)
                          (message wireless-signal-end))
  (let ((src-node (node (src message))))
    (dolist(receiver (aref (receivers wireless) (nodeid src-node)))
      (send-direct wireless receiver (duplicate message)))
    (setf (aref (receivers wireless) (nodeid src-node)) nil)))
