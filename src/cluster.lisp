(in-package :cl-user)
(defpackage legion.cluster
  (:use :cl)
  (:import-from :legion.worker
                :worker
                :make-worker
                :start-worker
                :stop-worker
                :kill-worker
                :worker-thread)
  (:import-from :legion.scheduler
                :make-round-robin-scheduler)
  (:import-from :bordeaux-threads
                :join-thread)
  (:export :cluster
           :make-cluster
           :cluster-status
           :cluster-workers
           :start-cluster
           :stop-cluster
           :kill-cluster
           :add-job-to-cluster))
(in-package :legion.cluster)

(defun make-workers-array (worker-num process-fn queue-size)
  (let ((workers (make-array worker-num :element-type 'worker)))
    (dotimes (i worker-num workers)
      (setf (svref workers i)
            (make-worker process-fn
                         :queue-size queue-size)))))

(defstruct (cluster (:constructor make-cluster
                        (worker-num process-fn &key (queue-size 128) scheduler
                         &aux
                           (workers (make-workers-array worker-num process-fn queue-size))
                           (scheduler (or scheduler
                                          (make-round-robin-scheduler workers))))))
  (status :shutdown)
  workers
  scheduler)

(defmethod print-object ((object cluster) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (format stream ":STATUS ~A :WORKER-NUM ~A"
            (cluster-status object)
            (length (cluster-workers object)))))

(defun start-cluster (cluster)
  (loop for worker across (cluster-workers cluster)
        do (start-worker worker))
  (setf (cluster-status cluster) :running)
  (vom:info "cluster has started.")
  cluster)

(defun stop-cluster (cluster)
  (loop for worker across (cluster-workers cluster)
        do (stop-worker worker))
  (setf (cluster-status cluster) :shutting)
  (loop for worker across (cluster-workers cluster)
        for thread = (worker-thread worker)
        when thread
          do (join-thread thread))
  (setf (cluster-status cluster) :shutdown)
  cluster)

(defun kill-cluster (cluster)
  (loop for worker across (cluster-workers cluster)
        do (kill-worker worker))
  (setf (cluster-status cluster) :shutdown)
  cluster)

(defun add-job-to-cluster (cluster job)
  (when (eq (cluster-status cluster) :shutting)
    (return-from add-job-to-cluster nil))
  (funcall (cluster-scheduler cluster)
           (cluster-workers cluster)
           job))