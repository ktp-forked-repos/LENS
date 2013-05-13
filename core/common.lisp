;; Some commonly used definitions and protocols
;; Copyright (C) 2011 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:


;;; Code:

(in-package :lens)

;; Basic types

(defconstant +c+ 299792458d0 "Speed of Light in m/sec")

(defparameter *context* nil
  "Current global context in which evaluation (e.g. random functions)
  is to be done.")

;; base class for in simulation errors (not program errors)
(define-condition simulation-condition(condition)())

;; Some basic macros
(defmacro while (test &body body)
  "A while loop - repeat body while test is true"
  `(do ()
    ((not ,test))
    ,@body))

(defmacro until (test &body body)
  "Repeat body until test returns true"
  `(do ()
    (,test)
    ,@body))

(defmacro filter(test lst &key (key '#'identity))
  "Return a list of the elements in `lst` for which `test` (applied to `key`)
is true.

Arguments:

- `test`: a designator for a function of one argument which returns a
          generalised boolean
- `lst`: a proper list
- `key`: a designator for a function of one argument

Returns:

- `result`: a list"
  `(mapcan #'(lambda(it)
               (when (funcall ,test (funcall ,key it))
                 (list it)))
    ,lst))

(defmacro for ((var start stop) &body body)
  (let ((gstop (gensym)))
    `(do ((,var ,start (1+ ,var))
          (,gstop ,stop))
      ((>= ,var ,gstop))
      ,@body)))

(defun copy-slots(slots source destination)
  "Copies anemd slot values shallowly from source to destination
returning the modifed destination object."
  (dolist(slot slots)
    (if (slot-boundp source slot)
        (setf (slot-value destination slot) (slot-value source slot))
        (slot-makunbound destination slot)))
  destination)

(defun wstrim(string) (string-trim '(#\space #\tab) string))

(defun property-union(list1 list2)
  "Returns a merged property list combining properties from list1 and
list2. list1 property will have priority excepti if the property
values are themselves a list in which case the result is list2 value
appended onto end of list1 value"
  (let ((result (copy-list list2)))
    (loop :for a :on list1 :by #'cddr
       :for k = (car a)
       :for v1 = (cadr a)
       :for v2 = (getf list2 k)
       :when v1
       :do (setf (getf result k)
                 (if (and (listp v1) (listp v2))
                     (append v1 v2)
                     v1)))
    result))