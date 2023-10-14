(defpackage #:org.shirakumo.fraf.trial.gjk
  (:use #:cl #:org.shirakumo.fraf.math)
  (:export))

(in-package #:org.shirakumo.fraf.trial.gjk)

(defconstant GJK-ITERATIONS 64)
(defconstant EPA-ITERATIONS 64)
(defconstant EPA-TOLERANCE 0.0001)
(defconstant EPA-MAX-FACES 64)
(defconstant EPA-MAX-LOOSE-EDGES 32)

;;;; GJK main algorithm
;; TODO: avoid consing from v-

(defstruct (point
            (:constructor point (&optional (varr3 (make-array 3 :element-type 'single-float))))
            (:include vec3)
            (:copier NIL)
            (:predicate NIL))
  (a (vec3 0 0 0) :type vec3)
  (b (vec3 0 0 0) :type vec3))

(trial:define-hit-detector (trial:primitive trial:primitive)
  (declare (optimize speed))
  (let ((s0 (point)) (s1 (point)) (s2 (point)) (s3 (point)) (dir (point)) (s12 (point)))
    (declare (dynamic-extent s0 s1 s2 s3 dir s12))
    (v<- dir (trial::global-location a))
    (nv- dir (trial::global-location b))
    (search-point s2 dir a b)
    (v<- dir s2)
    (nv- dir)
    (search-point s1 dir a b)
    (v<- s12 s2)
    (nv- s12 s1)
    (unless (< (v. s1 dir) 0)
      (!vc dir (!vc dir s12 (v- s1)) s12)
      (when (v= 0 dir)
        (!vc dir s12 +vx3+)
        (when (v= 0 dir)
          (!vc dir s12 +vz3+)))
      (loop with dim of-type (unsigned-byte 8) = 2
            for i from 0 below GJK-ITERATIONS
            do (search-point s0 dir a b)
               (when (< (v. s0 dir) 0)
                 (return))
               (incf dim)
               (cond ((= 3 dim)
                      (setf dim (update-simplex s0 s1 s2 s3 dir)))
                     ((null (test-simplex s0 s1 s2 s3 dir))
                      (setf dim 3))
                     (T
                      (epa s0 s1 s2 s3 a b trial:hit)
                      (trial:finish-hit)))))))

(trial:define-ray-test trial:primitive ()
  ;; TODO: Implement
  (trial:implement!))

(defun update-simplex (s0 s1 s2 s3 dir)
  (declare (optimize speed (safety 0)))
  (declare (type point s0 s1 s2 s3))
  (declare (type vec3 dir))
  (let ((n (vec3)) (ao (v- s0)))
    (declare (dynamic-extent n ao))
    (!vc n (v- s1 s0) (v- s2 s0))
    (cond ((< 0 (v. ao (vc (v- s1 s0) n)))
           (v<- s2 s0)
           (!vc dir (!vc dir (v- s1 s0) ao) (v- s1 s0))
           2)
          ((< 0 (v. ao (vc n (v- s2 s0))))
           (v<- s1 s0)
           (!vc dir (!vc dir (v- s2 s0) ao) (v- s2 s0))
           2)
          ((< 0 (v. n ao))
           (v<- s3 s2)
           (v<- s2 s1)
           (v<- s1 s0)
           (v<- dir n)
           3)
          (T
           (v<- s3 s1)
           (v<- s1 s0)
           (v<- dir n)
           (nv- dir)
           3))))

(defun test-simplex (s0 s1 s2 s3 dir)
  (declare (optimize speed (safety 0)))
  (declare (type point s0 s1 s2 s3))
  (declare (type vec3 dir))
  (let ((abc (vec3)) (acd (vec3)) (adb (vec3)) (ao (v- s0)))
    (declare (dynamic-extent abc acd adb ao))
    (!vc abc (v- s1 s0) (v- s2 s0))
    (!vc acd (v- s2 s0) (v- s3 s0))
    (!vc adb (v- s3 s0) (v- s1 s0))
    (cond ((< 0 (v. abc ao))
           (v<- s3 s2)
           (v<- s2 s1)
           (v<- s1 s0)
           (v<- dir abc)
           NIL)
          ((< 0 (v. acd ao))
           (v<- s1 s0)
           (v<- dir acd)
           NIL)
          ((< 0 (v. adb ao))
           (v<- s2 s3)
           (v<- s3 s1)
           (v<- s1 s0)
           (v<- dir adb)
           NIL)
          (T
           T))))

(defun search-point (p +dir a b)
  (declare (optimize speed))
  (declare (type point p))
  (declare (type vec3 +dir))
  (let ((-dir (v- +dir)))
    (declare (dynamic-extent -dir))
    (%support-function b +dir (point-b p))
    (%support-function a -dir (point-a p))
    (v<- p (point-b p))
    (nv- p (point-a p))))

;;;; EPA for depth and normal computation
;;; FIXME: stack allocation bullshit
(defun epa (s0 s1 s2 s3 a b hit)
  (declare (optimize speed (safety 1)))
  (declare (type point s0 s1 s2 s3))
  (declare (type trial:hit hit))
  (let ((faces (make-array (* 4 EPA-MAX-FACES)))
        (loose-edges (make-array (* 2 EPA-MAX-LOOSE-EDGES)))
        (num-faces 4) (closest-face 0) (min-dist 0.0)
        (search-dir (vec3)) (p (point)))
    (declare (dynamic-extent faces loose-edges search-dir p))
    (declare (type (unsigned-byte 16) num-faces))
    (macrolet ((v (f v)
                 `(aref faces (+ (* 4 ,f) ,v)))
               (e (e v)
                 `(aref loose-edges (+ (* 2 ,e) ,v))))
      (setf (v 0 0) s0)
      (setf (v 0 1) s1)
      (setf (v 0 2) s2)
      (setf (v 0 3) (nvunit* (vc (v- s1 s0) (v- s2 s0))))
      (setf (v 1 0) s0)
      (setf (v 1 1) s2)
      (setf (v 1 2) s3)
      (setf (v 1 3) (nvunit* (vc (v- s2 s0) (v- s3 s0))))
      (setf (v 2 0) s0)
      (setf (v 2 1) s3)
      (setf (v 2 2) s1)
      (setf (v 2 3) (nvunit* (vc (v- s3 s0) (v- s1 s0))))
      (setf (v 3 0) s1)
      (setf (v 3 1) s3)
      (setf (v 3 2) s2)
      (setf (v 3 3) (nvunit* (vc (v- s3 s1) (v- s3 s1))))

      ;; Main iteration loop to find the involved faces
      (dotimes (i EPA-ITERATIONS)
        (setf min-dist (v. (v 0 0) (v 0 3)))
        (setf closest-face 0)
        (loop for i from 1 below num-faces
              for dist = (v. (v i 0) (v i 3))
              do (when (< dist min-dist)
                   (setf min-dist dist)
                   (setf closest-face i)))
        (v<- search-dir (v closest-face 3))
        (search-point p search-dir a b)
        (when (< (- (v. p search-dir) min-dist) EPA-TOLERANCE)
          (return))
        (let ((num-loose-edges 0))
          (declare (type (unsigned-byte 16) num-loose-edges))
          ;; Find triangles facing our current search point
          (dotimes (i num-faces)
            (when (< 0 (v. (v i 3) (v- p (v i 0))))
              (loop for j from 0 below 3
                    for edge-a = (v i j)
                    for edge-b = (v i (mod (1+ j) 3))
                    for edge-found-p = NIL
                    do (dotimes (k num-loose-edges)
                         (when (and (eq (e k 1) edge-a) (eq (e k 0) edge-b))
                           (setf edge-a (e (1- num-loose-edges) 0))
                           (setf edge-b (e (1- num-loose-edges) 1))
                           (decf num-loose-edges)
                           (setf edge-found-p T)
                           (return)))
                       (unless edge-found-p
                         (when (<= EPA-MAX-LOOSE-EDGES num-loose-edges)
                           (return))
                         (setf (e num-loose-edges 0) edge-a)
                         (setf (e num-loose-edges 1) edge-b)
                         (incf num-loose-edges)))
              (setf (v i 0) (v (1- num-faces) 0))
              (setf (v i 1) (v (1- num-faces) 1))
              (setf (v i 2) (v (1- num-faces) 2))
              (setf (v i 3) (v (1- num-faces) 3))
              (decf num-faces)
              (decf i)))
          ;; Reconstruct the polytope with the search point added
          (dotimes (i num-loose-edges)
            (when (<= EPA-MAX-FACES num-faces) 
              (return))
            (setf (v num-faces 0) (e i 0))
            (setf (v num-faces 1) (e i 1))
            (setf (v num-faces 2) p)
            (setf (v num-faces 3) (nvunit* (vc (v- (e i 0) (e i 1)) (v- (e i 0) p))))
            ;; Check the CCW winding order via normal test
            (when (< (+ (v. (v num-faces 0) (v num-faces 3)) 0.000001) 0)
              (rotatef (v num-faces 0) (v num-faces 1))
              (nv- (v num-faces 3)))
            (incf num-faces))))
      
      ;; Compute the actual intersection
      ;; If we did not converge, we just use the closest face we reached.
      (let ((p (vec3)) (local-a (vec3)) (local-b (vec3)))
        (declare (dynamic-extent p local-a local-b))
        (multiple-value-bind (u v w) (barycentric (v closest-face 0) (v closest-face 1) (v closest-face 2)
                                                  (plane-point (v closest-face 0) (v closest-face 1) (v closest-face 2) p))
          (nv+* local-a (point-a (v closest-face 0)) u)
          (nv+* local-a (point-a (v closest-face 1)) v)
          (nv+* local-a (point-a (v closest-face 2)) w)
          (nv+* local-b (point-b (v closest-face 0)) u)
          (nv+* local-b (point-b (v closest-face 1)) v)
          (nv+* local-b (point-b (v closest-face 2)) w)
          (v<- (trial:hit-normal hit) local-a)
          (nv- (trial:hit-normal hit) local-b)
          (setf (trial:hit-depth hit) (vlength (trial:hit-normal hit)))
          (v<- (trial:hit-location hit) local-b)
          (if (= 0.0 (trial:hit-depth hit))
              (v<- (trial:hit-normal hit) +vy3+)
              (nv/ (trial:hit-normal hit) (trial:hit-depth hit))))))))

(defun barycentric (a b c p)
  (declare (optimize speed (safety 0)))
  (declare (type vec3 a b c p))
  (let* ((v0 (v- b a)) 
         (v1 (v- c a))
         (v2 (v- p a))
         (d00 (v. v0 v0))
         (d01 (v. v0 v1))
         (d11 (v. v1 v1))
         (d20 (v. v2 v0))
         (d21 (v. v2 v1))
         (denom (- (* d00 d11) (* d01 d01))))
    (declare (dynamic-extent v0 v1 v2))
    (if (<= denom 0.000001)
        (values 1 0 0)
        (let ((v (/ (- (* d11 d20) (* d01 d21)) denom))
              (w (/ (- (* d00 d21) (* d01 d20)) denom)))
          (values (- 1 v w) v w)))))

(defun plane-point (a b c &optional (res (vec3)))
  (declare (optimize speed (safety 0)))
  (declare (type vec3 a b c res))
  (let* ((normal (!vc res (v- b a) (v- c a)))
         (offset (- (v. normal a)))
         (mag2 (v. normal normal)))
    (when (< 1.0e-16 mag2)
      (let ((invmag (/ (sqrt mag2))))
        (nv* normal invmag)
        (setf offset (* offset invmag))))
    (nv* normal (- offset))))

;;;; Support function implementations
(defun %support-function (primitive global-direction next)
  (declare (optimize speed (safety 0)))
  (declare (type trial:primitive primitive))
  (declare (type vec3 global-direction next))
  (let ((local (vcopy3 global-direction)))
    (declare (dynamic-extent local))
    (trial::ntransform-inverse local (trial:primitive-transform primitive))
    (support-function primitive local next)
    (n*m next (trial:primitive-transform primitive))))

(defgeneric support-function (primitive local-direction next))

(defmacro define-support-function (type (dir next) &body body)
  `(defmethod support-function ((primitive ,type) ,dir ,next)
     (declare (type vec3 ,dir ,next))
     (declare (optimize speed))
     ,@body))

(define-support-function trial:plane (dir next)
  (let ((denom (v. (trial:plane-normal primitive) dir)))
    (vsetf next 0 0 0)
    (if (<= denom 0.000001)
        (nv+* next dir (trial:plane-offset primitive))
        (let ((tt (/ (trial:plane-offset primitive) denom)))
          (nv+* next dir tt)))))

(define-support-function trial:sphere (dir next)
  (nv* (nvunit* (v<- next dir)) (trial:sphere-radius primitive)))

(define-support-function trial:box (dir next)
  (let ((bsize (trial:box-bsize primitive)))
    (vsetf next
           (if (< 0 (vx3 dir)) (vx3 bsize) (- (vx3 bsize)))
           (if (< 0 (vy3 dir)) (vy3 bsize) (- (vy3 bsize)))
           (if (< 0 (vz3 dir)) (vz3 bsize) (- (vz3 bsize))))))

(define-support-function trial:pill (dir next)
  (nv* (nvunit* (v<- next dir)) (trial:pill-radius primitive))
  (let ((bias (- (trial:pill-height primitive) (trial:pill-radius primitive))))
    (if (< 0 (vy dir))
        (incf (vy next) bias)
        (decf (vy next) bias))))

(define-support-function trial:cylinder (dir next)
  (vsetf next (vx dir) 0 (vz dir))
  (nv* (nvunit* next) (trial:cylinder-radius primitive))
  (if (< 0 (vy dir))
      (incf (vy next) (trial:cylinder-height primitive))
      (decf (vy next) (trial:cylinder-height primitive))))

(define-support-function trial:triangle (dir next)
  (let ((furthest most-negative-single-float))
    (flet ((test (vert)
             (let ((dist (v. vert dir)))
               (when (< furthest dist)
                 (setf furthest dist)
                 (v<- next vert)))))
      (test (trial:triangle-a primitive))
      (test (trial:triangle-b primitive))
      (test (trial:triangle-c primitive)))))

(define-support-function trial:convex-mesh (dir next)
  (let ((verts (trial::convex-mesh-vertices primitive))
        (vert (vec3))
        (furthest most-negative-single-float))
    (declare (dynamic-extent vert))
    ;; FIXME: this is O(n)
    (loop for i from 0 below (length verts) by 3
          do (vsetf vert
                    (aref verts (+ i 0))
                    (aref verts (+ i 1))
                    (aref verts (+ i 2)))
             (let ((dist (v. vert dir)))
               (when (< furthest dist)
                 (setf furthest dist)
                 (v<- next vert))))))