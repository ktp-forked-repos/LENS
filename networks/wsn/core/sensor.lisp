;; Sensor implementation for WSN nodes
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

;;

;;; Code:
(in-package :lens.wsn)

(defstruct measurement
  "Structure representing a discrete measurement (with noise etc) by a
specific sensor"
  (location (make-coord) :type coord :read-only t)
  (time (simulation-time) :type time-type )
  (value 0 :type real)
  sensor)

(defclass sensor-message(message)
  ((measurement :type measurement :initform nil :initarg :measurement
                :accessor measurement))
  (:documentation "Message sent by a [[sensor]] to its' application
  gate when it has completed a measurement"))


(defclass sensor(wsn-module)
  ((power-consumption
    :parameter t :initform 0.02 :reader power-consumption
    :initarg :power-consumption :type float
    :documentation "Power consumption for this sensor in mJ")
   (physical-process-id
    :parameter t :type integer :reader physical-process-id
    :initarg :physical-process-id
    :documentation "Index of the physical process being measured by this sensor")
   (physical-process
    :type physical-process :reader physical-process
    :documentation "Actual physical process instance being measured by
    this sensor.")
   (measurand
    :parameter t :initform 'temperature :reader measurand
    :documentation "Type of reading from physical process
    e.g. humidity, temperature, light etc")
   (bias
    :parameter t :initform (normal 0 0.1 0)
    :initarg :bias :reader bias :format number-or-expression
    :documentation "Sensor Device offset reading")
   (noise
    :parameter t ::volatile t :initform (normal 0 0.1 1)
    :reader noise :initarg :noise :type float
    :documentation "stddev of Gaussian Noise for sensor")
   (sensitivity
    :parameter t :initform 0 :reader sensitivity :type float
    :documentation "The minimum value which can be sensed by
    each sensing device.")
   (resolution
    :parameter t :initform 0.001 :reader resolution :type float
    :documentation "The sensing resolution. the returned value
     will always be a multiple of this value.")
   (saturation
    :parameter t :initform 1000 :reader saturation :type float
    :documentation "The saturation value for each sensing device")
   (last-measurement :type measurement :accessor last-measurement)
   (sample-interval
    :parameter t :initform 0 :type real :reader sample-interval
    :documentation "Time interval between regular samples or 0 if not
    continually sampling")
   (measurement-delay
    :parameter t :initform 100e-6 :type real :reader measurement-delay
    :documentation "Conversion time - default is typical for AVR")
   (sample-timer :type message :accessor sample-timer
                   :initform nil :documentation "sampling self messsge")
   (measurement-timer
    :initform nil :type sensor-message :accessor measurement-timer
    :documentation "Self measurement message"))
  (:gates
   (application :inout))
  (:metaclass module-class)
  (:default-initargs :num-rngs 2)
  (:documentation "Module representing a single sensor on a
  [[node]]. Sensors may either operate in continual sampling mode or
  in responsive mode (if sample-interval is 0).

In responsive mode there will be measurement-delay delay between
request message and sending back a reading message. If in sampling mode
thern the message will correspond to the last sampled time."))


(defmethod initialize-instance :after ((sensor sensor) &key &allow-other-keys)
  (with-slots(measurement-delay sample-interval bias) sensor
    (assert (or (zerop sample-interval)
                (> sample-interval measurement-delay))
            ()
            "Sample interval ~A is less than measurement time of ~A"
            sample-interval measurement-delay)
  #+nil(unless (numberp bias)
    (let ((*context* sensor))
      (setf (slot-value sensor 'bias) (eval bias))))))

(defmethod initialize list ((sensor sensor) &optional (stage 0))
  (case stage
    (0
     (unless (slot-boundp sensor 'physical-process-id)
       (setf (slot-value  sensor 'physical-process-id) (index sensor)))
     (setf (slot-value sensor 'physical-process)
           (submodule (network sensor)
                      'physical-processes
                      :index (physical-process-id sensor)))
     nil)
    (1
     ;; emit must be stage 1 so all listeners subscribed
     ;; castelia doesn't record this correctly
     #-castelia-compatability
     (emit sensor 'power-change (power-consumption sensor))
     t)))

(defmethod startup((instance sensor))
  (when (not (zerop (sample-interval instance)))
    (setf (measurement-timer instance)
          (make-instance 'sensor-message
                         :owner instance :name 'measurement))
    (setf (sample-timer instance)
          (make-instance 'message :owner instance :name 'sensor-sample))
    (set-timer instance (sample-timer instance) (sample-interval instance))))

(defmethod shutdown ((sensor sensor))
  (when (sample-timer sensor)
    (cancel (sample-timer sensor)))
  (when (measurement-timer sensor)
    (cancel (measurement-timer sensor))))

(defun sensor-measurement(sensor)
  "Return a sensor value reading at this time"
  (let* ((location (location (node sensor)))
         (time (simulation-time))
         (value (measure (physical-process sensor) (measurand sensor)
                         location time))
         (noise (noise sensor))
         (bias (bias sensor)))
    (tracelog "Value=~,3f bias=~,3f noise=~,3f" value bias noise)
    (with-slots(resolution sensitivity saturation) sensor
      (make-measurement
       :sensor sensor
       :location location
       :time time
       :value (* resolution
                 (floor
                  (min saturation
                       (max sensitivity
                            (+ bias value noise)))
                       resolution))))))

(defmethod handle-message((sensor sensor) message)
  (cond
    ((eql message (sample-timer sensor))
     ;; regular sampling - schedule to upddate last-measurement after
     ;; measurement-delay and resample after sample interval
     (let ((m (measurement-timer sensor)))
       (setf (measurement m) (sensor-measurement sensor))
       (set-timer sensor m  (measurement-delay sensor))
       (set-timer sensor message  (sample-interval sensor))))
    ((eql message (measurement-timer sensor))
     ;; this is sampling self measurement message so update last-measurement
     (setf (last-measurement sensor) (measurement sensor)))
    ((typep message 'sensor-message)
     ;; measurement message from somewhere else
     (cond
       ((measurement message) ;; already has measurement so send out
        (send sensor message 'application))
       ((zerop (sample-interval sensor))
        ;; no sampling so take reading and schedule measurement for
        ;; measurement later
        (setf (measurement message) (sensor-measurement sensor))
        (set-timer sensor message (measurement-delay sensor)))
       (t
        ;; we are sampling so return last-measurement in message
        (setf (measurement message) (last-measurement sensor))
        (send sensor message 'application))))
    (t
     (warn 'unknown-message :module sensor :message message))))
