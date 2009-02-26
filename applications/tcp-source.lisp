;; tcp application base
;; Copyright (C) 2007 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :application)

(defclass tcp-source(application)
  ((protocol :type tcp :reader protocol
             :documentation "The tcp (layer 4) protocol instance")
   (peer-address :initarg :peer-address :initform nil :type ipaddr
                 :reader peer-address
                 :documentation "IP address of peer to send to")
   (peer-port  :initarg :peer-port :initform nil
               :type ipport :reader peer-port
               :documentation "Port of peer to send to")
   (sleep-time :initarg :sleep-time :reader sleep-time
               :documentation "Random time to sleep between transmissions")
   (data-size :initarg :data-size :reader data-size
              :documentation "Random size of data to send")
   (loop-count :initarg loop-count :initform 1 :accessor loop-count)
   (repeat-count :initform 0 :accessor repeat-count)
   (bytes-sent :initform 0 :accessor bytes-sent
               :documentation "Bytes sent this loop")
   (bytes-ack :initform 0 :accessor bytes-ack
              :documentation "Bytes acknowledged this loop")
   (connectedp :initform nil :accessor connectedp
               :documentation "True if already connected")
   (endedp :initform nil :accessor endedp
           :documentation "True if all data sent"))
  (:documentation "An application that sends a random amount of data
to a TCP server.  The application will optionally sleep for a random
amount of time and send some more data, up to a user specified limit
on the number of sending iterations."))

(defmethod initialize-instance((app tcp-source)
                               &key (tcp-variant tcp:*default-tcp-variant*)
                               node &allow-other-keys)
  (setf (slot-value app 'protocol)
        (make-instance tcp-variant :application app :node node)))

(defmethod send-data((app tcp-source))
  (if (connectedp app)
      (progn
        (let* ((sent (max 1 (random-value (data-size app))))
               (data (make-instance 'data
                                 :size sent
                                 :msg-size sent
                                 :response-size 0)))
          (setf (bytes-sent app) sent
                (bytes-ack app) 0)
          (send data (protocol app))))
      (connect (peer-address app) (peer-port app) (protocol app))))


(defmethod start((app tcp-source))
  (stop app)
  (send-data app))

(defmethod reset((app tcp-source))
  (stop app)
  (reset (protocol app))
  (setf (repeat-count app) 0
        (bytes-sent app) 0
        (bytes-ack app) 0
        (endedp app) nil))

(defmethod stop((app tcp-source) &key abort)
  (declare (ignore abort))
  (cancel app))

(defmethod handle((app tcp-source))
  (send-data app))

(defmethod connection-complete((app tcp-source) tcp)
  (declare (ignore tcp))
  (setf (connectedp app) t)
  (send-data app))

(defmethod connection-failed((app tcp-source) tcp)
  (declare (ignore tcp))
  (warn "~S connection failed - peer ~S" app (peer-address app)))

(defmethod sent((app tcp-source) c tcp)
  (when (> c 0)
    (incf (bytes-ack app) c)
    (when (>= (bytes-ack app) (bytes-sent app))
      (if (<= (incf (repeat-count app)) (loop-count app))
          (schedule (random-value (sleep-time app)) app)
          (progn
            (setf (endedp app) t)
            (close-connection tcp))))))









