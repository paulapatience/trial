(in-package #:org.shirakumo.fraf.trial.examples)

(define-example scene-loader
  :title "Load Arbitrary Scenes"
  :superclasses (trial:physics-scene)
  :slots ((physics-system :initform (make-instance 'accelerated-rigidbody-system :units-per-metre 0.1))
          (file :initform NIL :accessor file))
  (enter (make-instance 'vertex-entity :vertex-array (// 'trial 'grid)) scene)
  (enter (make-instance 'editor-camera :location (VEC3 10.0 20 14) :rotation (vec3 0.75 5.5 0.0) :fov 50 :move-speed 0.1) scene)
  (enter (make-instance 'directional-light :direction -vy3+) scene)
  (enter (make-instance 'ambient-light :color (vec3 0.5)) scene)
  (enter (make-instance 'gravity :gravity (vec 0 -10 0)) scene)
  (let ((render (make-instance 'pbr-render-pass))
        (map (make-instance 'ward)))
    (connect (port render 'color) (port map 'previous-pass) scene)))

(defmethod setup-ui ((scene scene-loader-scene) panel)
  (let ((layout (make-instance 'alloy:grid-layout :col-sizes '(120 140 T) :row-sizes '(30)))
        (focus (make-instance 'alloy:vertical-focus-list)))
    (alloy:enter "Load File" layout :row 0 :col 0)
    (let ((button (alloy:represent "..." 'alloy:button :layout-parent layout :focus-parent focus)))
      (alloy:on alloy:activate (button)
        (let ((file (org.shirakumo.file-select:existing :title "Load Model File..."
                                                        :filter '(("glTF Binary" "glb")
                                                                  ("glTF File" "gltf"))
                                                        :default (file scene))))
          (when file (setf (file scene) file)))))
    (alloy:finish-structure panel layout focus)))

(defmethod (setf file) :after (file (loader scene-loader-scene))
  (generate-resources 'model-loader file :load-scene T)
  (commit loader (loader +main+)))