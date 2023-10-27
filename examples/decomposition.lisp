(in-package #:org.shirakumo.fraf.trial.examples)

(define-shader-entity decomposition-entity (vertex-entity colored-entity transformed-entity)
  ((panel :initarg :panel :accessor panel)
   (visible-p :initarg :visible-p :initform T :accessor visible-p)))

(defmethod render :around ((entity decomposition-entity) (program shader-program))
  (when (visible-p entity)
    (gl:polygon-mode :front-and-back (polygon-mode (panel entity)))
    (call-next-method)
    (gl:polygon-mode :front-and-back :fill)))

(defclass decomposition-panel (trial-alloy:panel)
  ((container :initarg :container :accessor container)
   (model :initform NIL :accessor model)
   (mesh :initform NIL :accessor mesh)
   (polygon-mode :initform :fill :accessor polygon-mode)
   (show-original :initform NIL :accessor show-original)
   (file :initform NIL :accessor file)))

(alloy:define-observable (setf model) (value alloy:observable))
(alloy:define-observable (setf mesh) (value alloy:observable))

(defmethod initialize-instance :after ((panel decomposition-panel) &key)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(120 140 T) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (alloy:enter "Load Model" layout :row 0 :col 0)
    (let ((button (alloy:represent "..." 'alloy:button :layout-parent layout :focus-parent focus)))
      (alloy:on alloy:activate (button)
        (let ((file (org.shirakumo.file-select:existing :title "Load Model File..."
                                                        :filter '(("Wavefront OBJ" "obj")
                                                                  ("glTF File" "gltf")
                                                                  ("glTF Binary" "glb"))
                                                        :default (file panel))))
          (when file (setf (file panel) file)))))
    (alloy:enter "Mesh" layout :row 1 :col 0)
    (let* ((mesh NIL)
           (selector (alloy:represent mesh 'alloy:combo-set :value-set () :layout-parent layout :focus-parent focus)))
      (alloy:on model (model panel)
        (let ((meshes (if (typep model 'model) (list-meshes model) ())))
          (setf (alloy:value-set selector) meshes)
          (when meshes (setf (mesh panel) (find-mesh (first meshes) model)))))
      (alloy:on alloy:value (mesh selector)
        (setf (mesh panel) (find-mesh mesh (model panel)))))
    (alloy:enter "Show Original" layout :row 2 :col 0)
    (alloy:represent (show-original panel) 'alloy:switch :layout-parent layout :focus-parent focus)
    (alloy:enter "Wireframe" layout :row 3 :col 0)
    (alloy:represent (polygon-mode panel) 'alloy:switch :layout-parent layout :focus-parent focus
                                                        :on :line :off :fill)
    (alloy:finish-structure panel layout focus)
    (load (assets:asset :woman))
    (setf (model panel) (assets:asset :woman))))

(defmethod (setf file) :before (file (panel decomposition-panel))
  (setf (model panel) (generate-resources 'model-loader file)))

(defmethod (setf show-original) :after (value (panel decomposition-panel))
  (let ((orig (node :original (container panel))))
    (when orig (setf (visible-p orig) value))))

(defmethod (setf mesh) :before ((mesh mesh-data) (panel decomposition-panel))
  (clear (container panel))
  (enter (make-instance 'decomposition-entity
                        :name :original
                        :panel panel
                        :color (vec 1 1 1 0.5)
                        :visible-p (show-original panel)
                        :vertex-array (make-vertex-array 
                                       (make-convex-mesh
                                        :vertices (reordered-vertex-data mesh '(location))
                                        :faces (trial::simplify (index-data mesh) '(unsigned-byte 32)))
                                       NIL))
         (container panel))
  (loop for hull across (org.shirakumo.fraf.convex-covering:decompose
                         (reordered-vertex-data mesh '(location))
                         (trial::simplify (index-data mesh) '(unsigned-byte 32)))
        for (name . color) in (apply #'alexandria:circular-list (colored:list-colors))
        do (enter (make-instance 'decomposition-entity
                                 :panel panel
                                 :color (vec (colored:r color) (colored:g color) (colored:b color))
                                 :vertex-array (make-vertex-array (make-convex-mesh :vertices (org.shirakumo.fraf.convex-covering:vertices hull)
                                                                                    :faces (org.shirakumo.fraf.convex-covering:faces hull))
                                                                  NIL))
                  (container panel)))
  (commit (scene +main+) (loader +main+)))

(define-example decomposition
  :title "Convex Hull Decomposition"
  (let ((game (make-instance 'render-pass))
        (ui (make-instance 'ui))
        (combine (make-instance 'blend-pass)))
    (connect (port game 'color) (port combine 'a-pass) scene)
    (connect (port ui 'color) (port combine 'b-pass) scene))
  (enter (make-instance 'vertex-entity :vertex-array (// 'trial 'grid)) scene)
  (enter (make-instance 'editor-camera :location (VEC3 0.0 2.3 10) :fov 50 :move-speed 0.1) scene)
  (let ((container (make-instance 'array-container)))
    (enter container scene)
    (trial-alloy:show-panel 'decomposition-panel :container container)))
