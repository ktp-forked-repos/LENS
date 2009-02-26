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

(defclass point-to-point(link)
  ((local-interface
    :type interface :initarg :local-interface :accessor local-interface
    :documentation "The local (sending) interface of this link")
   (peer-interface
    :initform nil :type interface
    :initarg :peer-interface :accessor peer-interface
    :documentation "The remote (receiving) interfaceon this link"))
  (:documentation "A serial point to point link"))

(defmethod peer-interfaces((link point-to-point))
  (when (peer-interface link)
    (list (peer-interface link))))

(defmethod transmit(link packet interface node &optional rate)
  (declare (ignore rate))
  (transmit-helper link packet interface (peer-interface link)))

(defmethod ip-to-mac(ipaddr (link point-to-point))
  (let ((peer (peer-interface link)))
    (when (address= ipaddr (ipaddr peer))
      (macaddr peer))))

(defmethod peer-node-p((node node) (link point-to-point))
  (eql node (node (peer-interface link))))

(defmethod default-peer-interface((link point-to-point))
  (peer-interface link))

(defmethod peer-node-ipaddr((node node) (link point-to-point))
  (declare (ignore node))
  (ipaddr (peer-interface link)))


