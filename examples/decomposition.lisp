(in-package #:org.shirakumo.fraf.trial.examples)

(define-shader-entity decomposition-entity (vertex-entity colored-entity transformed-entity)
  ((hull :initarg :hull :reader hull)
   (original-color :initarg :original-color :accessor original-color)
   (polygon-mode :initarg :polygon-mode :initform nil :accessor polygon-mode)
   (panel :initarg :panel :accessor panel)
   (scene :initarg :scene :accessor scene)
   (visible-p :initarg :visible-p :initform T :accessor visible-p)))

(defmethod spaces:location ((object decomposition-entity))
  (let* (; (debug-info (org.shirakumo.fraf.convex-covering::debug-info (hull object)))
         ; (hull (getf debug-info :hull))
         (patch (hull object))
         (hull (org.shirakumo.fraf.convex-covering::patch-hull patch)))
    (spaces:location hull)))

(defmethod spaces:bsize ((object decomposition-entity))
  (let* (; (debug-info (org.shirakumo.fraf.convex-covering::debug-info (hull object)))
         ; (hull (getf debug-info :hull))
         (patch (hull object))
         (hull (org.shirakumo.fraf.convex-covering::patch-hull patch)))
    (spaces:bsize hull)))

(defmethod render-with :around ((pass render-pass) (entity decomposition-entity) (program shader-program))
  (when (visible-p entity)
    (gl:polygon-mode :front-and-back (or (polygon-mode entity)
                                         (polygon-mode (scene +main+))))
    (call-next-method)
    (gl:polygon-mode :front-and-back :fill)))

(defclass mesh-item (alloy:combo-item) ())
(defmethod alloy:text ((item mesh-item)) (name (alloy:value item)))

(defmethod alloy:combo-item ((item mesh-data) (combo alloy:combo))
  (make-instance 'mesh-item :value item))

(define-example decomposition
  :title "Convex Hull Decomposition"
  :superclasses (alloy:observable)
  :slots ((model :initform NIL :accessor model)
          (mesh :initform NIL :accessor mesh)
          (polygon-mode :initform :fill :accessor polygon-mode)
          (show-original :initform NIL :accessor show-original)
          (show-decomposition :initform NIL :accessor show-decomposition)
          (file :initform NIL :accessor file)
          ;;
          (index :initform (org.shirakumo.fraf.trial.space.kd-tree:make-kd-tree
                            :dimensions 3)
                 :reader index)
          (selection-buffer :initform (make-instance 'selection-buffer) :accessor selection-buffer)
          (selection1 :initform '() :accessor selection1)
          (selection2 :initform '() :accessor selection2)
          (debug-entities :initform '() :accessor debug-entities)
          (context :initform nil :accessor context))
  (enter (make-instance 'render-pass) scene)
  (enter (make-instance 'vertex-entity :vertex-array (// 'trial 'grid)) scene)
  (enter (make-instance 'editor-camera :location (VEC3 0.0 2.3 10) :fov 50 :move-speed 0.1) scene)
  (enter (make-instance 'basic-node :name :container) scene))

(defun selected-patch1 (scene)
  (first (selection1 scene)))

(defun selected-patch2 (scene)
  (first (selection2 scene)))

(alloy:define-observable (setf model) (value alloy:observable))
(alloy:define-observable (setf mesh) (value alloy:observable))

(defmethod setup-ui ((scene decomposition-scene) panel)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(120 140 T) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (alloy:enter "Load Model" layout :row 0 :col 0)
    (let ((button (alloy:represent "..." 'alloy:button :layout-parent layout :focus-parent focus)))
      (alloy:on alloy:activate (button)
        (let ((file (org.shirakumo.file-select:existing :title "Load Model File..."
                                                        :filter '(("Wavefront OBJ" "obj")
                                                                  ("glTF File" "gltf")
                                                                  ("glTF Binary" "glb"))
                                                        :default (file scene))))
          (when file (setf (file scene) file)))))
    (alloy:enter "Mesh" layout :row 1 :col 0)
    (let ((selector (alloy:represent (mesh scene) 'alloy:combo-set :value-set () :layout-parent layout :focus-parent focus)))
      (alloy:on model (model scene)
        (let ((meshes (if (typep model 'model) (list-meshes model) ())))
          (setf (alloy:value-set selector) meshes)
          (when meshes (setf (alloy:value selector) (first meshes)))))
      (alloy:on alloy:value (mesh selector)
        (setf (mesh scene) mesh)))
    (alloy:enter "Show Original" layout :row 2 :col 0)
    (alloy:represent (show-original scene) 'alloy:switch :layout-parent layout :focus-parent focus)
    (alloy:enter "Show Decomposition" layout :row 3 :col 0)
    (alloy:represent (show-decomposition scene) 'alloy:switch :layout-parent layout :focus-parent focus)
    (alloy:enter "Wireframe" layout :row 4 :col 0)
    (alloy:represent (polygon-mode scene) 'alloy:switch :layout-parent layout :focus-parent focus
                                                        :on :line :off :fill)
    (load (assets:asset :woman))
    (setf (model scene) (assets:asset :woman))
    (alloy:finish-structure panel layout focus)))

(defmethod stage :after ((scene decomposition-scene) (area staging-area))
  (stage (selection-buffer scene) area))

(defmethod (setf file) :before (file (scene decomposition-scene))
  (setf (model scene) (generate-resources 'model-loader file)))

(defmethod (setf show-original) :after (value (scene decomposition-scene))
  (let ((orig (node :original scene)))
    (when orig (setf (visible-p orig) value))))

(defmethod (setf show-decomposition) :after (value (scene decomposition-scene))
  )

(defmethod (setf mesh) :before ((mesh mesh-data) (scene decomposition-scene))
  (clear (node :container scene))
  (spaces:clear (index scene))
  (multiple-value-bind (all-vertices all-faces)
      (org.shirakumo.fraf.manifolds:normalize
       (reordered-vertex-data mesh '(location))
       (trial::simplify (index-data mesh) '(unsigned-byte 32))
       :threshold .000001)
    (enter (make-instance 'decomposition-entity
                          :name :original
                          :scene scene
                          :color (vec 1 1 1 0.5)
                          :visible-p (show-original scene)
                          :transform (transform (vec -3 0 0))
                          :vertex-array (make-vertex-array
                                         (make-convex-mesh :vertices all-vertices :faces all-faces)
                                         NIL))
           (node :container scene))
    (multiple-value-bind (hulls context)
        (let ((org.shirakumo.fraf.convex-covering::*debug-output* nil)
              (org.shirakumo.fraf.convex-covering::*debug-visualizations* nil))
          (org.shirakumo.fraf.convex-covering:decompose all-vertices all-faces))
      (setf (context scene) context)
      (loop for hull across hulls
            for vertices = (org.shirakumo.fraf.convex-covering:vertices hull)
            for faces = (org.shirakumo.fraf.convex-covering:faces hull)
            for (name . color) in (apply #'alexandria:circular-list (colored:list-colors))
            for color* = (vec (colored:r color) (colored:g color) (colored:b color))
            for debug-info = (org.shirakumo.fraf.convex-covering::debug-info hull)
            for patch =      (getf debug-info :patch)
            for entity = (make-instance 'decomposition-entity
                                        :hull patch
                                        :scene scene
                                        :original-color color*
                                        :color color*
                                        :visible-p (show-decomposition scene)
                                        ; :transform (transform (vec 3 0 0))
                                        :vertex-array (make-vertex-array (make-convex-mesh :vertices vertices
                                                                                           :faces faces)
                                                                         NIL))
            do (enter entity (node :container scene))
               (enter entity (selection-buffer scene))
               (enter entity (index scene)))))
  (commit (scene +main+) (loader +main+)))

(defun clear-debug-entities (scene)
  (let ((container (node :container scene)))
    (map nil (lambda (entity) (leave entity container))
         (debug-entities scene)))
  (setf (debug-entities scene) '()))

(defun add-debug-hull (patch color scene)
  (let ((hull (org.shirakumo.fraf.convex-covering::patch-hull patch)))
    (when hull
      (loop for (centroid . normal) in (org.shirakumo.fraf.convex-covering::hull-facet-normals
                                        hull)
            for entity = (debug-line (vec centroid) (vec (v+ centroid (v* normal .5)))
                                     :debug-draw nil
                                     :container (node :container scene)
                                     :color (v* color .4))
            do (push entity (debug-entities scene))))

    (multiple-value-bind (vertices faces)
        (if hull
            (values (org.shirakumo.fraf.convex-covering::hull-vertices hull)
                    (org.shirakumo.fraf.convex-covering::hull-facets hull))
            (values (org.shirakumo.fraf.convex-covering::context-vertices (context scene))
                    (org.shirakumo.fraf.convex-covering::patch-faces patch)))
      (multiple-value-bind (vertices faces)
          (org.shirakumo.fraf.manifolds:normalize
           (map-into (make-array (length vertices) :element-type 'single-float)
                     (lambda (c) (coerce c 'single-float))
                     vertices)
           (trial::simplify faces '(unsigned-byte 32))
           :threshold .000001)
        (let* ((mesh (make-convex-mesh :vertices vertices :faces faces))
               (entity (make-instance 'decomposition-entity :hull patch
                                                            :scene scene
                                                            :original-color color
                                                            :color color
                                                            :visible-p t
                                                            :polygon-mode :fill
                                                            :vertex-array (make-vertex-array mesh NIL))))
          (push entity (debug-entities scene))
          (enter entity (node :container scene))
          entity)))))

(defun patch-merged-patches (patch)
  (let* ((patch      (hull patch))
         ; (debug-info (org.shirakumo.fraf.convex-covering::debug-info hull))
         ; (patch      (getf debug-info :patch))
         (link       (org.shirakumo.fraf.convex-covering::patch-link patch))
         (a          (org.shirakumo.fraf.convex-covering::patch-link-a link))
         (b          (org.shirakumo.fraf.convex-covering::patch-link-b link)))
    (values a b)))

(defun explain-merge (patch decomposition-panel)
  (let ((link (org.shirakumo.fraf.convex-covering::patch-link patch)))
    (when link
      (let ((a (org.shirakumo.fraf.convex-covering::patch-link-a link))
            (b (org.shirakumo.fraf.convex-covering::patch-link-b link)))
        (add-debug-hull a (vec 0 1 0 1) decomposition-panel)
        (add-debug-hull b (vec 1 0 0 1) decomposition-panel)

        (spaces:do-all (patch (index decomposition-panel))
          (setf (color patch) (vec .3 .3 .3)
                (polygon-mode patch) :line))))))

(define-handler (decomposition-scene mouse-press :after) (button pos)
  (flet ((compute-selection (old-selection)
           (let* ((camera-position (vxyz (org.shirakumo.fraf.math.matrices:m* (minv (view-matrix)) (vec4 0 0 0 1))))
                  (camera-forward  (org.shirakumo.fraf.math.matrices:m* (view-matrix) (vec4 0 0 1 0)))
                  (camera-forward  (vec (vxy camera-forward) (- (vz camera-forward)))))
             (format *trace-output* "pos ~A~%fwd ~A~%" camera-position camera-forward)
             (let ((hits '()))
               (spaces:do-intersecting (patch (index decomposition-scene) camera-position camera-forward)
                 (push patch hits))
               (let ((new-selection (if (alexandria:set-equal hits old-selection)
                                        (let ((first (pop old-selection)))
                                          (append old-selection (list first)))
                                        hits)))

                 (format *trace-output* "Selection ~A~%" new-selection)
                 new-selection)))))
    (case button
      (:left
       (let ((object (select (pos mouse-press) (selection-buffer decomposition-scene))))
         (setf (selection1 decomposition-scene) (if object (list object) '()))))
      (:right
       (let ((object (select (pos mouse-press) (selection-buffer decomposition-scene))))
         (setf (selection2 decomposition-scene) (if object (list object) '())))))
    (case button
      ((:left :right)
       (clear-debug-entities decomposition-scene)
       (let ((selected1 (selected-patch1 decomposition-scene))
             (selected2 (selected-patch2 decomposition-scene)))
         (spaces:do-all (patch (index decomposition-scene))
           (setf (visible-p patch) t)
           (cond ((or (eq patch selected1) (eq patch selected2))
                  (setf (polygon-mode patch) :fill))
                 (t
                  (setf (color patch) (original-color patch)
                        (polygon-mode patch) nil)))))))))

(define-handler (decomposition-scene key-press :after) (key)
  (flet ((debug-patch (patch)
           (let* ((hull       (hull patch))
                  (debug-info (org.shirakumo.fraf.convex-covering::debug-info hull)))
             (clouseau:inspect debug-info :new-process t))))
    (case (print key *trace-output*)
      (:1 (debug-patch (selected-patch1 decomposition-scene)))
      (:2 (debug-patch (selected-patch2 decomposition-scene)))
      (:e                               ; explain
       (let ((patch1 (selected-patch1 decomposition-scene))
             (patch2 (selected-patch2 decomposition-scene)))
         (cond ((and patch1 (not patch2)) ; why was this created?
                (format *trace-output* "Why merged ~A?~%" patch1)
                (setf (polygon-mode patch1) :line)
                (let* ((patch       (hull patch1))
                                        ; (debug-info (org.shirakumo.fraf.convex-covering::debug-info hull))
                                        ; (patch      (getf debug-info :patch))
                       )
                  (explain-merge patch decomposition-scene)))
               ((and patch1 patch2)     ; why were these not merged?
                (format *trace-output* "Why not merged ~A and ~A?~%" patch1 patch2))
               ))
       (commit (scene +main+) (loader +main+)))
      (:g
       (clear-debug-entities decomposition-scene)
       (let* ((selection1 (selected-patch1 decomposition-scene))
              (patch      (patch-merged-patches selection1))
              (entity     (add-debug-hull patch (original-color selection1) decomposition-scene)))
         (setf (polygon-mode entity) :line)
         (setf (selection1 decomposition-scene) (list entity))
         (explain-merge patch decomposition-scene))
       (commit (scene +main+) (loader +main+)))
      (:r
       (clear-debug-entities decomposition-scene)
       (let* ((selection1 (selected-patch1 decomposition-scene))
              (patch      (nth-value 1 (patch-merged-patches selection1)))
              (entity     (add-debug-hull patch (original-color selection1) decomposition-scene)))
         (setf (polygon-mode entity) :line)
         (setf (selection1 decomposition-scene) (list entity))
         (explain-merge patch decomposition-scene))
       (commit (scene +main+) (loader +main+)))
      (:v
       (let* ((selection1 (selected-patch1 decomposition-scene))
              (patch      (hull selection1))
              (context    (context decomposition-scene)))
         (let ((*print-circle* t)
               (*print-level* 3)
               (*print-length* 3))
           (let ((org.shirakumo.fraf.convex-covering::*debug-visualizations* t))
             (org.shirakumo.fraf.convex-covering::valid-patch-p patch context))
           (clouseau:inspect patch :new-process t)
           (let ((hull (org.shirakumo.fraf.convex-covering::patch-hull patch)))
             (when hull
               (format *trace-output* "annotations ~A~%" (org.shirakumo.fraf.convex-covering::hull-annotations hull))
               (loop with container = (node :container decomposition-scene)
                     for (kind . data) in (org.shirakumo.fraf.convex-covering::hull-annotations hull)
                     for entity = (case kind
                                    (:point (debug-point (vec data)
                                                         :debug-draw nil :container container))
                                    (:line (debug-line (vec (car data)) (vec (cdr data))
                                                       :debug-draw nil :container container)))
                     do (format *trace-output* "~A~%" entity)
                     do (push entity (debug-entities decomposition-scene)))))))))))
