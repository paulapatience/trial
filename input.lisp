#|
 This file is a part of trial
 (c) 2016 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)

(define-global +input-source+ :keyboard)

(define-event input-event (event))
(define-event keyboard-event (input-event))
(define-event digital-event (input-event))

(defgeneric button (digital-event))

(define-event key-event (keyboard-event digital-event)
  (key arg! :reader key :reader button) (repeat NIL :reader repeat-p) (modifiers ()))

(defmethod print-object ((event key-event) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~s" (key event))))

(define-event key-press (key-event))
(define-event key-release (key-event))

(define-event text-entered (keyboard-event)
  text (replace NIL :reader replace-p))

(defmethod print-object ((event text-entered) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~s" (text event))))

(define-event mouse-event (input-event)
  pos)

(define-event mouse-button-event (mouse-event digital-event)
  button)

(defmethod print-object ((event mouse-button-event) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~s" (button event))))

(define-event mouse-press (mouse-button-event))
(define-event mouse-release (mouse-button-event))
(define-event mouse-double-click (mouse-button-event))
(define-event mouse-scroll (mouse-event)
  delta)

(defmethod print-object ((event mouse-scroll) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~a" (delta event))))

(define-event mouse-move (mouse-event)
  old-pos)

(defmethod print-object ((event mouse-move) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~a => ~a" (old-pos event) (pos event))))

(define-event file-drop-event (mouse-event)
  paths)

(define-event gamepad-event (input-event)
  device)

(define-event gamepad-button-event (gamepad-event digital-event)
  button)

(defmethod print-object ((event gamepad-button-event) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~a ~s" (device event) (button event))))

(define-event gamepad-press (gamepad-button-event))
(define-event gamepad-release (gamepad-button-event))

(define-event gamepad-move (gamepad-event)
  axis old-pos pos)

(defmethod print-object ((event gamepad-move) stream)
  (print-unreadable-object (event stream :type T)
    (format stream "~a ~s ~3f" (device event) (axis event) (pos event))))

(define-event gamepad-added (gamepad-event))
(define-event gamepad-removed (gamepad-event))
