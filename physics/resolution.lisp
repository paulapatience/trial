(in-package #:org.shirakumo.fraf.trial)

(defstruct (contact (:include hit))
  (to-world (mat3) :type mat3)
  (velocity (vec3 0 0 0) :type vec3)
  (desired-delta 0.0 :type single-float)
  (a-relative (vec3 0 0 0) :type vec3)
  (b-relative (vec3 0 0 0) :type vec3)
  (a-rotation-change (vec3 0 0 0) :type vec3)
  (b-rotation-change (vec3 0 0 0) :type vec3)
  (a-velocity-change (vec3 0 0 0) :type vec3)
  (b-velocity-change (vec3 0 0 0) :type vec3))

(defun hit-basis (hit &optional (basis (mat3)))
  (declare (optimize speed (safety 1)))
  (declare (type hit hit))
  (let ((normal (hit-normal hit))
        (tangent-0 (vec3 0 0 0))
        (tangent-1 (vec3 0 0 0)))
    (declare (dynamic-extent tangent-0 tangent-1))
    (declare (type mat3 basis))
    (cond ((< (abs (vy normal)) (abs (vx normal)))
           (let ((s (/ (sqrt (the (single-float 0.0)
                                  (+ (* (vz normal) (vz normal))
                                     (* (vx normal) (vx normal))))))))
             (vsetf tangent-0 (* (vz normal) s) 0.0 (- (* (vx normal) s)))
             (vsetf tangent-1
                    (* (vy normal) (vz tangent-0))
                    (- (* (vz normal) (vx tangent-0))
                       (* (vx normal) (vz tangent-0)))
                    (- (* (vy normal) (vx tangent-0))))))
          (T
           (let ((s (/ (sqrt (the (single-float 0.0)
                                  (+ (* (vz normal) (vz normal))
                                     (* (vy normal) (vy normal))))))))
             (vsetf tangent-0 0.0 (- (* (vz normal) s)) (* (vy normal) s))
             (vsetf tangent-1
                    (- (* (vy normal) (vz tangent-0))
                       (* (vz normal) (vy tangent-0)))
                    (- (* (vx normal) (vz tangent-0)))
                    (* (vx normal) (vy tangent-0))))))
    (with-fast-matref (m basis)
      (setf (m 0 0) (vx normal))
      (setf (m 0 1) (vx tangent-0))
      (setf (m 0 2) (vx tangent-1))
      (setf (m 1 0) (vy normal))
      (setf (m 1 1) (vy tangent-0))
      (setf (m 1 2) (vy tangent-1))
      (setf (m 2 0) (vz normal))
      (setf (m 2 1) (vz tangent-0))
      (setf (m 2 2) (vz tangent-1))
      basis)))

(defun local-velocity (to-world entity loc dt target)
  (declare (optimize speed (safety 1)))
  (declare (type vec3 loc target))
  (declare (type single-float dt))
  (let* ((vel (ntransform-inverse
               (nv+ (!vc target (the vec3 (rotation entity)) loc)
                    (the vec3 (velocity entity)))
               to-world))
         (tmp (the vec3 (last-frame-acceleration entity)))
         (acc (ntransform-inverse (nv* tmp dt) to-world)))
    (declare (dynamic-extent tmp))
    (setf (vx acc) 0f0)
    (nv+ vel acc)))

(defun desired-delta-velocity (hit velocity dt)
  (declare (optimize speed (safety 1)))
  (declare (type hit hit))
  (declare (type vec3 velocity))
  (declare (type single-float dt))
  (flet ((acc (entity)
           (let ((tmp (vec3)))
             (declare (dynamic-extent tmp))
             (v. (!v* tmp (the vec3 (last-frame-acceleration entity)) dt) (hit-normal hit)))))
    (let ((vel-from-acc (- (acc (hit-a hit)) (acc (hit-b hit))))
          (restitution (hit-restitution hit))
          (vx (vx velocity)))
      (when (< (abs vx) 0.25) ; Some kinda velocity limit magic number?
        (setf restitution 0.0))
      (+ (- vx) (* (- restitution) (- vx vel-from-acc))))))

(defun upgrade-hit-to-contact (hit dt)
  (declare (optimize speed (safety 1)))
  (declare (type contact hit))
  (declare (type single-float dt))
  (let* ((to-world (hit-basis hit (contact-to-world hit)))
         (a-relative (!v- (contact-a-relative hit) (hit-location hit) (the vec3 (location (hit-a hit)))))
         (b-relative (!v- (contact-b-relative hit) (hit-location hit) (the vec3 (location (hit-b hit)))))
         (a-velocity (vec3)) (b-velocity (vec3)))
    (declare (dynamic-extent a-velocity b-velocity))
    (local-velocity to-world (hit-a hit) a-relative dt a-velocity)
    (local-velocity to-world (hit-b hit) b-relative dt b-velocity)
    (!v- (contact-velocity hit) a-velocity b-velocity)
    (setf (contact-desired-delta hit) (desired-delta-velocity hit (contact-velocity hit) dt))
    (vsetf (contact-a-rotation-change hit) 0 0 0)
    (vsetf (contact-a-velocity-change hit) 0 0 0)
    (vsetf (contact-b-rotation-change hit) 0 0 0)
    (vsetf (contact-b-velocity-change hit) 0 0 0)
    hit))

(defun match-awake-state (contact)
  (declare (type contact contact))
  (let ((a (contact-a contact))
        (b (contact-b contact)))
    (when (and (/= 0 (inverse-mass a))
               (/= 0 (inverse-mass b))
               (xor (awake-p a) (awake-p b)))
      (if (awake-p a)
          (setf (awake-p b) T)
          (setf (awake-p a) T)))))

(defun frictionless-impulse (contact &optional (impulse (vec3 0 0 0)))
  (declare (type contact contact))
  (declare (type vec3 impulse))
  (declare (optimize speed (safety 1)))
  (flet ((body-delta-vel (loc body)
           (let ((delta-vel (vec3)))
             (declare (dynamic-extent delta-vel))
             (!vc delta-vel loc (contact-normal contact))
             (n*m (the mat3 (world-inverse-inertia-tensor body)) delta-vel)
             (!vc delta-vel delta-vel loc)
             (+ (the single-float (inverse-mass body)) (v. delta-vel (contact-normal contact))))))
    (vsetf impulse
           (/ (contact-desired-delta contact)
              (+ (body-delta-vel (contact-a-relative contact) (contact-a contact))
                 (body-delta-vel (contact-b-relative contact) (contact-b contact))))
           0.0
           0.0)))

(defun frictionful-impulse (contact &optional (impulse (vec3 0 0 0)))
  (declare (type contact contact))
  (declare (type vec3 impulse))
  (declare (optimize speed (safety 1)))
  (flet ((delta-vel (delta-velocity loc inverse-inertia-tensor)
           (declare (type mat3 inverse-inertia-tensor))
           (let* ((impulse-to-torque (mat 0 (- (vz loc)) (vy loc)
                                          (vz loc) 0 (- (vx loc))
                                          (- (vy loc)) (vx loc) 0))
                  (delta-vel-world (mcopy impulse-to-torque)))
             (declare (dynamic-extent impulse-to-torque delta-vel-world))
             (nm* delta-vel-world inverse-inertia-tensor)
             (nm* delta-vel-world impulse-to-torque)
             (nm* delta-vel-world -1)
             (nm+ delta-velocity delta-vel-world))))
    (let ((inverse-mass (+ (the single-float (inverse-mass (contact-a contact)))
                           (the single-float (inverse-mass (contact-b contact)))))
          (delta-velocity (mat3)))
      (declare (dynamic-extent delta-velocity))
      (declare (type mat3 delta-velocity))
      (when (< 0.0 (the single-float (inverse-mass (contact-a contact))))
        (delta-vel delta-velocity (contact-a-relative contact)
                   (world-inverse-inertia-tensor (contact-a contact))))
      (when (< 0.0 (the single-float (inverse-mass (contact-b contact))))
        (delta-vel delta-velocity (contact-b-relative contact)
                   (world-inverse-inertia-tensor (contact-b contact))))
      (nm* delta-velocity (contact-to-world contact))
      (!m* delta-velocity (mtranspose (contact-to-world contact)) delta-velocity)
      (with-fast-matref (m delta-velocity)
        (incf (m 0 0) inverse-mass)
        (incf (m 1 1) inverse-mass)
        (incf (m 2 2) inverse-mass))
      (let* ((vel-kill (vec (contact-desired-delta contact)
                            (- (vy (contact-velocity contact)))
                            (- (vz (contact-velocity contact)))))
             (impulse-matrix (mat3))
             (impulse (!m* impulse (!minv impulse-matrix delta-velocity) vel-kill))
             (planar-impulse (sqrt (the (single-float 0.0) (+ (expt (vy impulse) 2) (expt (vz impulse) 2)))))
             (friction (contact-dynamic-friction contact)))
        (declare (dynamic-extent vel-kill impulse-matrix))
        (when (< (* (vx impulse) (contact-static-friction contact)) planar-impulse)
          (setf (vy impulse) (/ (vy impulse) planar-impulse))
          (setf (vz impulse) (/ (vz impulse) planar-impulse))
          (setf (vx impulse) (/* (contact-desired-delta contact)
                                 (+ (miref delta-velocity 0)
                                    (* (miref delta-velocity 1) friction (vy impulse))
                                    (* (miref delta-velocity 2) friction (vz impulse)))))
          (setf (vy impulse) (* (vy impulse) friction (vx impulse)))
          (setf (vz impulse) (* (vz impulse) friction (vx impulse))))
        impulse))))

(defclass rigidbody-system (physics-system)
  ((velocity-eps :initform 0.01 :initarg :velocity-eps :accessor velocity-eps)
   (depth-eps :initform 0.01 :initarg :depth-eps :accessor depth-eps)
   (hits :initform (map-into (make-array 1024) #'make-contact))))

(defmethod (setf units-per-metre) (units (system rigidbody-system))
  ;; The default we pick here is for assuming 1un = 1cm
  (call-next-method)
  (setf (velocity-eps system) (* units 0.01))
  (setf (depth-eps system) (* units 0.01)))

(defgeneric collides-p (a b hit))
(defgeneric resolve-collision (a b contact))
(defgeneric impart-collision (entity contact linear angular))
(defgeneric resolve-collision-impact (a b contact))
(defgeneric impart-collision-impact (entity contact velocity rotation))

(defmethod collides-p ((a rigidbody) (b rigidbody) hit)
  T)

(defmethod resolve-collision ((a rigidbody) (b rigidbody) contact)
  (declare (optimize speed (safety 1)))
  (declare (type contact contact))
  (flet ((angular-inertia (entity loc)
           (let ((cross (vec3)))
             (declare (dynamic-extent cross))
             (!vc cross loc (contact-normal contact))
             (n*m (the mat3 (world-inverse-inertia-tensor entity)) cross)
             (!vc cross cross loc)
             (v. cross (contact-normal contact))))
         (linear-inertia (entity)
           (the single-float (inverse-mass entity)))
         (change (entity loc angular-inertia linear-inertia total-inertia
                         angular-change linear-change)
           (let ((angular-move (* (contact-depth contact)
                                  (/ angular-inertia total-inertia)))
                 (linear-move (* (contact-depth contact)
                                 (/ linear-inertia total-inertia)))
                 (projection (v* (contact-normal contact)
                                 (- (v. loc (contact-normal contact))))))
             (nv+ projection loc)
             (let ((max (* 0.2       ; Some kinda angular limit magic.
                           (vlength projection)))
                   (total (+ angular-move linear-move)))
               (cond ((< angular-move (- max))
                      (setf angular-move (- max))
                      (setf linear-move (- total angular-move)))
                     ((< max angular-move)
                      (setf angular-move max)
                      (setf linear-move (- total angular-move))))
               (cond ((= 0 angular-move)
                      (vsetf angular-change 0 0 0))
                     (T
                      (let ((target-direction (!vc angular-change loc (contact-normal contact)))
                            (inverse-tensor (the mat3 (world-inverse-inertia-tensor entity))))
                        (n*m inverse-tensor target-direction)
                        (nv* angular-change (/ angular-move angular-inertia)))))
               (!v* linear-change (contact-normal contact) linear-move)
               (impart-collision entity contact linear-change angular-change)
               (unless (awake-p entity)
                 (%update-rigidbody-cache entity))))))
    (let* ((a (contact-a contact))
           (b (contact-b contact))
           (a-angular-inertia (angular-inertia a (contact-a-relative contact)))
           (b-angular-inertia (angular-inertia b (contact-b-relative contact)))
           (a-linear-inertia (linear-inertia a))
           (b-linear-inertia (linear-inertia b))
           (total-inertia (+ a-angular-inertia b-angular-inertia
                             a-linear-inertia b-linear-inertia)))
      (unless (= 0 (the single-float (inverse-mass a)))
        (change a (contact-a-relative contact) a-angular-inertia a-linear-inertia total-inertia
                (contact-a-rotation-change contact) (contact-a-velocity-change contact)))
      (unless (= 0 (the single-float (inverse-mass b)))
        (change b (contact-b-relative contact) b-angular-inertia b-linear-inertia (- total-inertia)
                (contact-b-rotation-change contact) (contact-b-velocity-change contact))))))

(defmethod impart-collision ((entity rigidbody) contact linear angular)
  (nv+ (the vec3 (location entity)) (the vec3 linear))
  (nq+* (the quat (orientation entity)) (the vec3 angular) 1.0))

(defmethod resolve-collision-impact ((a rigidbody) (b rigidbody) contact)
  (declare (optimize speed (safety 1)))
  (declare (type contact contact))
  (let ((impulse (vec 0 0 0)))
    (declare (dynamic-extent impulse))
    (if (and (= 0 (contact-static-friction contact))
             (= 0 (contact-dynamic-friction contact)))
        (frictionless-impulse contact impulse)
        (frictionful-impulse contact impulse))
    (n*m (contact-to-world contact) impulse)
    (let ((entity (contact-a contact))
          (velocity-change (contact-a-velocity-change contact))
          (rotation-change (contact-a-rotation-change contact)))
      (unless (= 0.0 (the single-float (inverse-mass entity)))
        (!vc rotation-change (contact-a-relative contact) impulse)
        (n*m (the mat3 (world-inverse-inertia-tensor entity)) rotation-change)
        (!v* velocity-change impulse (the single-float (inverse-mass entity)))
        (impart-collision-impact entity contact velocity-change rotation-change)))
    ;; Second body needs to invert the direction.
    (let ((entity (contact-b contact))
          (velocity-change (contact-b-velocity-change contact))
          (rotation-change (contact-b-rotation-change contact)))
      (unless (= 0.0 (the single-float (inverse-mass entity)))
        (!vc rotation-change impulse (contact-b-relative contact))
        (n*m (the mat3 (world-inverse-inertia-tensor entity)) rotation-change)
        (!v* velocity-change impulse (- (the single-float (inverse-mass entity))))
        (impart-collision-impact entity contact velocity-change rotation-change)))))

(defmethod impart-collision-impact ((entity rigidbody) contact velocity rotation)
  (nv+ (the vec3 (velocity entity)) (the vec3 velocity))
  (nv+ (the vec3 (rotation entity)) (the vec3 rotation)))

(defun prune-hits (hits start new-start)
  (loop for head from start below new-start
        for hit = (aref hits start)
        do (when (collides-p (hit-a hit) (hit-b hit) hit)
             (rotatef (aref hits start) (aref hits head))
             (incf start)))
  start)

(defmethod generate-hits ((system rigidbody-system) hits start end)
  ;; If this seems inefficient to you, it is! Use the ACCELERATED-RIGIDBODY-SYSTEM instead.
  (loop with objects = (%objects system)
        for i from 0 below (length objects)
        for a = (aref objects i)
        do (loop for j from (1+ i) below (length objects)
                 for b = (aref objects j)
                 do (unless (and (= 0.0 (inverse-mass a))
                                 (= 0.0 (inverse-mass b)))
                      ;; Don't bother detecting hits between immovable objects
                      (loop for a-p across (physics-primitives a)
                            do (loop for b-p across (physics-primitives b)
                                     for new-start = (detect-hits a-p b-p hits start end)
                                     do (setf start (prune-hits hits start new-start)))))))
  start)

(defmethod resolve-hits ((system rigidbody-system) contacts start end dt &key (iterations 200))
  (declare (type (simple-array contact (*)) contacts))
  (declare (type (unsigned-byte 32) start end iterations))
  (declare (type single-float dt))
  (declare (optimize speed))
  (macrolet ((do-contacts ((contact) &body body)
               `(loop for i from start below end
                      for ,contact = (aref contacts i)
                      do (progn ,@body)))
             (do-update (args &body body)
               `(do-contacts (other)
                  (flet ((change ,args
                           ,@body))
                    (when (eq (contact-a other) (contact-a contact))
                      (change (contact-a-rotation-change contact)
                              (contact-a-velocity-change contact)
                              (contact-a-relative other) -1))
                    (when (eq (contact-a other) (contact-b contact))
                      (change (contact-b-rotation-change contact)
                              (contact-b-velocity-change contact)
                              (contact-a-relative other) -1))
                    (when (eq (contact-b other) (contact-a contact))
                      (change (contact-a-rotation-change contact)
                              (contact-a-velocity-change contact)
                              (contact-b-relative other) +1))
                    (when (eq (contact-b other) (contact-b contact))
                      (change (contact-b-rotation-change contact)
                              (contact-b-velocity-change contact)
                              (contact-b-relative other) +1))))))
    ;; Prepare Contacts
    (do-contacts (contact)
      (upgrade-hit-to-contact contact dt))

    ;; Adjust Positions
    (loop repeat iterations
          for worst = (the single-float (depth-eps system))
          for contact = NIL
          do (do-contacts (tentative)
               (when (< worst (contact-depth tentative))
                 (setf contact tentative)
                 (setf worst (contact-depth contact))))
             (unless contact (return))
             (match-awake-state contact)
             (resolve-collision (hit-a contact) (hit-b contact) contact)
             ;; We now need to fix up the contact depths.
             (do-update (rotation-change velocity-change loc sign)
               (let ((cross (vec3)))
                 (declare (dynamic-extent cross))
                 (!vc cross rotation-change loc)
                 (incf (contact-depth other)
                       (* sign (v. (nv+ cross velocity-change)
                                   (contact-normal other)))))))

    ;; Adjust Velocities
    (loop repeat iterations
          for worst = (the single-float (velocity-eps system)) ;; Some kinda epsilon.
          for contact = NIL
          do (do-contacts (tentative)
               (when (< worst (contact-desired-delta tentative))
                 (setf contact tentative)
                 (setf worst (contact-desired-delta contact))))
             (unless contact (return))
             (match-awake-state contact)
             (resolve-collision-impact (hit-a contact) (hit-b contact) contact)
             (when (< 0.0 (contact-desired-delta contact))
               (do-update (rotation-change velocity-change loc sign)
                 (let ((cross (vec3)))
                   (declare (dynamic-extent cross))
                   (!vc cross rotation-change loc)
                   (ntransform-inverse (nv+ cross velocity-change) (contact-to-world other))
                   (nv+* (contact-velocity other) cross (- sign))
                   (setf (contact-desired-delta other)
                         (desired-delta-velocity other (contact-velocity other) dt))))))))

(defclass accelerated-rigidbody-system (rigidbody-system)
  ((acceleration-structure :initform (org.shirakumo.fraf.trial.space.kd-tree:make-kd-tree) :accessor acceleration-structure)
   (pending-inserts :initform (make-array 128 :fill-pointer 0) :accessor pending-inserts)))

(defmethod enter :before ((body rigidbody) (system accelerated-rigidbody-system))
  (cond ((= 0 (length (physics-primitives body)))
         (unless (find body (pending-inserts system))
           (vector-push-extend body (pending-inserts system))))
        (T
         (start-frame body)
         (loop with structure = (acceleration-structure system)
               for primitive across (physics-primitives body)
               do (3ds:enter primitive structure)))))

(defmethod leave :after ((body rigidbody) (system accelerated-rigidbody-system))
  (unless (array-utils:vector-pop-element* (pending-inserts system) body)
    (loop with structure = (acceleration-structure system)
          for primitive across (physics-primitives body)
          do (3ds:leave primitive structure))))

(defmethod integrate :after ((system accelerated-rigidbody-system) dt)
  (loop with structure = (acceleration-structure system)
        for object across (%objects system)
        do (loop for primitive across (physics-primitives object)
                 do (3ds:update primitive structure))))

(defmethod generate-hits ((system accelerated-rigidbody-system) hits start end)
  (3ds:do-pairs (a b (acceleration-structure system) start)
    (let ((entity1 (primitive-entity a))
          (entity2 (primitive-entity b)))
      (unless (or (eq entity1 entity2)
                  (and (= 0.0 (inverse-mass entity1))
                       (= 0.0 (inverse-mass entity2))))
        (setf start (prune-hits hits start (detect-hits a b hits start end)))
        (when (<= end start) (return start))))))

(defmethod start-frame :before ((system accelerated-rigidbody-system))
  (let ((pending-inserts (pending-inserts system))
        (structure (acceleration-structure system)))
    (loop while (< 0 (length pending-inserts))
          for body = (vector-pop pending-inserts)
          do (start-frame body)
             (loop for primitive across (physics-primitives body)
                   do (3ds:enter primitive structure)))))

;;;

(defclass debug-rigidbody-mixin ()
  ((include-fixed-p :initarg :include-fixed-p
                    :accessor include-fixed-p
                    :initform NIL)
   (debug-instances :reader debug-instances
                    :initform (make-hash-table :test #'eq))
   (generation      :accessor generation
                    :initform 0)))

(flet ((debug-bbox (system object location bsize color)
         (let* ((debug-instances (debug-instances system))
                (generation (generation system))
                (info (gethash object debug-instances))
                (old-id (when info (car info)))
                (id (debug-box location bsize :color color :instance old-id)))
           (when info
             (setf (cdr info) generation))
           (unless old-id
             (setf (gethash object debug-instances) (cons id generation))))))

  (defmethod start-frame :after ((system debug-rigidbody-mixin))
    (let ((generation (generation system)))
      (when (block nil
              (maphash (lambda (entity info)
                         (when (/= (cdr info) generation)
                           (return T)))
                       (debug-instances system)))
        (debug-clear)
        (clrhash (debug-instances system)))
      (setf (generation system) (1+ generation)))
    (let ((structure (acceleration-structure system)))
      (labels ((visit (node depth)
                 (let* ((min (org.shirakumo.fraf.trial.space.kd-tree::node-bb-min node))
                        (max (org.shirakumo.fraf.trial.space.kd-tree::node-bb-max node))
                        (bsize (v/ (v- max min) 2))
                        (location (v+ min bsize)))
                   (debug-bbox system node location bsize (vec3 0 (/ (+ 1 depth)) 0)))
                 (typecase node
                   (org.shirakumo.fraf.trial.space.kd-tree::inner-node
                    (visit (org.shirakumo.fraf.trial.space.kd-tree::node-near node) (1+ depth))
                    (visit (org.shirakumo.fraf.trial.space.kd-tree::node-far node) (1+ depth))))))
        (visit (org.shirakumo.fraf.trial.space.kd-tree::kd-tree-root structure) 0))))

  (defmethod generate-hits :around ((system debug-rigidbody-mixin) contacts start end)
    (labels ((interesting-entity-p (entity)
               (not (= 0.0 (inverse-mass entity))))
             (interesting-entity-pair-p (entity1 entity2)
               (case (include-fixed-p system)
                 ((T)
                  T)
                 (:mixed
                  (or (interesting-entity-p entity1)
                      (interesting-entity-p entity2)))
                 ((NIL)
                  (and (interesting-entity-p entity1)
                       (interesting-entity-p entity2))))))
      (let* ((broadphase-pairs '())
             (collision-pairs '())
             (result (let ((start start))
                       (3ds:do-pairs (a b (acceleration-structure system) start)
                         (let ((entity1 (primitive-entity a))
                               (entity2 (primitive-entity b)))
                           (unless (or (eq entity1 entity2)
                                       (and (= 0.0 (inverse-mass entity1))
                                            (= 0.0 (inverse-mass entity2))))
                             (push (cons a b) broadphase-pairs)
                             (let ((new-start (detect-hits a b contacts start end)))
                               (when (> new-start start)
                                 (push (cons a b) collision-pairs))
                               (setf start new-start))
                             (when (<= end start) (return start)))))))
             (drawn '()))
        (labels ((draw-primitive (primitive color)
                   (when (not (find primitive drawn))
                     (push primitive drawn)
                     (let ((location (3ds:location primitive))
                           (bsize (3ds:bsize primitive)))
                       (debug-bbox system primitive location bsize color))))
                 (draw-phase (pairs color)
                   (loop for (a . b) in pairs
                         when (interesting-entity-pair-p (primitive-entity a)
                                                         (primitive-entity b))
                         do (draw-primitive a color)
                            (draw-primitive b color))))
          (draw-phase collision-pairs (vec3 1 0 0))
          (draw-phase broadphase-pairs (vec3 .8 .8 0)))
        result))))
