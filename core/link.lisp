;; $Id$
;; <description>
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :link)

(defvar *default-bandwidth* 1e6 "Default link bandwidth")
(defvar *default-delay* 1e-3 "Default link delay")
(defvar *default-jitter* (random-variable 'constant 0)
  "Default random variable for link transmission jitter")

;; this is equivalent to link-real in GTNetS
(defclass link()
  ((bandwidth
    :type number :initarg :bandwidth :accessor bandwidth
    :initform *default-bandwidth*
    :documentation "Link andwidth in bits/sec")
   (delay
    :type number :initarg :delay :initform *default-delay*
    :documentation "Link Propagation Delay in sec")
   (jitter :accessor jitter :initarg :jitter
           :initform *default-jitter*
           :documentation "Jitter in packet transmission time to simulate
variable processing delayes in routers")
   (bit-error-rate :type number :initarg :bit-error-rate
                   :accessor bit-error-rate :initform 0
                   :documentation "Bit Error Rate for this link")
   (ber-rnd :initform (random-variable 'uniform) :reader ber-rnd
            :allocation :class
            :documentation "Bit error rate random number generation")
   (weight :type number :initarg :weight :accessor weight :initform 1
    :documentation "Link weight (for some routing protocols)")
   (bytes-sent :type integer :initform 0 :accessor bytes-sent
               :documentation "Total packets sent on this link")
   (packets-sent :type integer :initform 0 :accessor packets-sent
                 :documentation "Total packets sent on this link")
   (busy-p :initform nil :accessor busy-p
           :documentation "Busy state of link")
   (utilisation-start
    :type time-type :initform (simulation-time)
    :accessor utilisation-start
    :documentation "Start of utilization measurement interval")
   (notifications :accessor notifications :initform (make-instance 'queue)
                  :type queue
                  :documentation "Objects to notify when link not busy"))
  (:documentation "Base Class for all links"))

(defgeneric delay(link &optional local-interface peer-interface)
  (:documentation "Return the propagation delay in bits/sec between
interfaces over link")
  (:method((link link) &optional a b)
    (declare (ignore a b))
    (slot-value link 'delay)))

(defmethod print-object((link link) stream)
  (print-unreadable-object (link stream :type t :identity t)
    (format stream "~0:/print-eng/bit/sec ~0:/print-eng/sec delay"
            (bandwidth link) (delay link))))

(defmethod reset((link link))
  (reset-utilisation link)
  (reset (notifications link)))

(defgeneric peer-interfaces(link)
  (:documentation "Return a sequence of the peer interfaces this link
connects to"))

(defgeneric peer-node-p(node link)
  (:documentation "Return true of node is a peer of link")
  (:method((node node) (link link))
    (find node (peer-interfaces link) :key #'node)))

(defgeneric ip-to-mac(ipaddr link)
  (:documentation "Return MAC address for given ipaddr on link")
  (:method(ipaddr link)
    (when-bind(interface (find ipaddr (peer-interfaces link)
                               :key #'ipaddr :test #'address=))
      (macaddr interface))))

(defgeneric find-interface(addr link)
  (:documentation "Return an interface given an addr on link")
  (:method((macaddr macaddr) link)
    (find macaddr (peer-interfaces link) :key #'macaddr :test #'address=)))

(defgeneric peer-node-ipaddr(node link)
  (:documentation "Return the peer ipaddress of given node on link")
  (:method((node node) (link link))
    (let ((peer (find node (peer-interfaces link) :key #'interface:node)))
      (when peer (ipaddr peer)))))

(defgeneric rx-own-broadcast(link)
  (:documentation "If true interfaces receive their own braodcast")
  (:method(link) (declare (ignore link)) nil))

(defgeneric default-peer-interface(link)
  (:documentation "Return the default peer (gateway) on a link"))

(defvar *default-link* '(point-to-point)
  "List of default arguments for make-instance to make a default link")

(defun utilisation(link)
  (let ((now (simulation-time)))
    (if (= now (utilisation-start link))
        0
        (/ (* 8 (bytes-sent link))
           (* (bandwidth link) (- now (utilisation-start link)))))))

(defun reset-utilisation(link)
  (setf (utilisation-start link) (simulation-time)
        (packets-sent link) 0
        (bytes-sent link) 0))

(defgeneric transmit(link packet interface node &optional rate)
  (:documentation "Transmit a packet over link"))

(defgeneric link(entity)
  (:documentation "Return the link associated with an entity"))

(defgeneric transmit-complete(link local-interface bytes-sent)
  (:documentation "Record a completed transmission")
  (:method((link link) local-interface bytes-sent)
    (incf (bytes-sent link) bytes-sent)
    (incf (packets-sent link))
    (setf (busy-p link) nil)
    (notify (extract-head (notifications link)))
    (notify local-interface)))

(defun transmit-helper(link packet local-interface peer-interface
                       &optional broadcast)
  (let* ((no-bits (* 8 (size packet)))
         (lostp
          (with-slots(bit-error-rate ber-rnd) link
             (when (not (zerop bit-error-rate))
               (< (random-value ber-rnd)
                  (- 1 (expt (- 1 bit-error-rate) no-bits))))))
         (txtime (/ no-bits (bandwidth link)))
         (delay (delay link))
         (jitter (random-value (jitter link)))
         (rxtime (+ txtime delay jitter)))
    (when (notification packet)
      (insert (notification packet) (notifications link)))
    (setf (notification packet) nil)
    (when (busy-p link)
      (error "Attempt to send a packet over a busy link"))
    (setf (busy-p link) t)
    ;; schedule packet transmit complete event
    (schedule txtime
              (list #'transmit-complete link local-interface (size packet)))
    ;; schedule packet arrival at interface(s)
    (if broadcast
        (dolist(i (peer-interfaces link))
          (unless (and (eql i local-interface) (not (rx-own-broadcast link)))
            (schedule-timer
             rxtime #'interface:receive i (copy packet) lostp)))
        (schedule-timer
         rxtime #'interface:receive peer-interface packet lostp))))

(defgeneric make-new-interface(link &key ipaddr ipmask)
  (:documentation "Make a new interface for given type of link"))
