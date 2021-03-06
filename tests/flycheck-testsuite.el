;;; flycheck-testsuite.el --- Testsuite for Flycheck -*- lexical-binding: t; -*-

;; Copyright (c) 2013 Sebastian Wiesner <lunaryorn@gmail.com>
;;
;; Author: Sebastian Wiesner <lunaryorn@gmail.com>
;; URL: https://github.com/lunaryorn/flycheck

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Entry point of the Flycheck test suite.

;; Test discovery and loading
;; --------------------------
;;
;; Find and load all tests.
;;
;; Test files and directories must match the
;; `flycheck-testsuite-test-file-pattern'.  Essentially this pattern matches all
;; directories and files starting with the prefix "test-".
;;
;; `flycheck-testsuite-load-tests' finds and loads all tests.

;; Resource handling
;; -----------------
;;
;; These functions can be used to load resources within a test.
;;
;; `flycheck-testsuite-resource-filename' gets the file name of resources.
;;
;; `flycheck-testsuite-with-resource-buffer' executes forms with a temporary
;; buffer using a resource file from the test suite.

;; Test helpers
;; ------------
;;
;; `flycheck-testsuite-with-hook' executes the body with a specified hook form.

;; Test environment utilities
;; --------------------------
;;
;; `flycheck-testsuite-windows-p' determines whether the tests are running on
;; Windows.
;;
;; `flycheck-testsuite-min-emacs-version-p' determines whether Emacs has at
;; least the given version.
;;
;; `flycheck-testsuite-user-error-type' provides the type of `user-error',
;; depending on the Emacs version.

;; Test results
;; ------------
;;
;; The following functions are intended for use with as value for the
;; `:expected-result' keyword to `ert-deftest'.
;;
;; `flycheck-testsuite-fail-unless-checkers' marks a test as expected to fail if
;; the given syntax checkers are not installed.

;; Checking buffers
;; ----------------
;;
;; The following functions can be used to perform syntax checks in a test.
;;
;; `flycheck-testsuite-buffer-sync' starts a syntax check in the current buffer
;; and waits for the syntax check to complete.
;;
;; `flycheck-testsuite-wait-for-syntax-checker' waits until the syntax check in
;; the current buffer is finished.
;;
;; `flycheck-testsuite-disable-checkers' disables syntax checkers in the current
;; buffers.

;; Test predicates
;; ---------------
;;
;; `flycheck-testsuite-should-errors' tests that the current buffer has ERRORS.
;;
;; `flycheck-testsuite-should-syntax-check' tests that a syntax check results in
;; the specified errors.
;;
;; `flycheck-testsuite-ensure-clear' clear the error state of the current
;; buffer, and signals a test failure if clearing failed.


;;; Code:

(require 'flycheck)

(require 'ert)

(require 'dash)
(require 's)

;;;; Directories
(defconst flycheck-testsuite-dir
  (if load-file-name
      (file-name-directory load-file-name)
    ;; Fall back to default directory (in case of M-x eval-buffer)
    default-directory)
  "The testsuite directory.")

(defconst flycheck-testsuite-resources-dir
  (expand-file-name "resources" flycheck-testsuite-dir)
  "Directory of test resources.")


;;;; Test discovery and loading
(defconst flycheck-testsuite-test-file-pattern "^.*/test-[^/]+$"
  "Regular expression to match names of test files.")

(defun flycheck-testsuite-test-file-p (filename)
  "Determine whether FILENAME is a test file."
  (and (s-matches? flycheck-testsuite-test-file-pattern filename)
       (file-regular-p filename)))

(defun flycheck-testsuite-test-dir-p (dirname)
  "Determine whether DIRNAME is a test directory."
  (and (s-matches? flycheck-testsuite-test-file-pattern dirname)
       (file-directory-p dirname)))

(defun flycheck-testsuite-find-all-test-files (directory)
  "Recursively all test files in DIRECTORY."
  (let* ((contents (directory-files directory :full-names))
         (test-files (-filter 'flycheck-testsuite-test-file-p contents))
         (test-dirs (-filter 'flycheck-testsuite-test-dir-p contents)))
    (append test-files
            (-flatten (-map 'flycheck-testsuite-find-all-test-files test-dirs))
            nil)))

(defun flycheck-testsuite-find-tests ()
  "Find all tests in the `flycheck-testsuite-dir'."
  (flycheck-testsuite-find-all-test-files flycheck-testsuite-dir))

(defun flycheck-testsuite-load-testfile (testfile)
  "Load a TESTFILE."
  (let ((default-directory (file-name-directory testfile)))
    (load testfile nil :no-message)))

(defun flycheck-testsuite-load-tests ()
  "Load all test files."
  (-each (flycheck-testsuite-find-tests) 'flycheck-testsuite-load-testfile))


;;;; Testsuite resource handling
(defun flycheck-testsuite-resource-filename (resource-file)
  "Determine the absolute file name of a RESOURCE-FILE.

Relative file names are expanded against
`flycheck-testsuite-resource-dir'."
  (expand-file-name resource-file flycheck-testsuite-resources-dir))

(defmacro flycheck-testsuite-with-resource-buffer (resource-file &rest body)
  "Create a temp buffer from a RESOURCE-FILE and execute BODY.

The absolute file name of RESOURCE-FILE is determined with
`flycheck-testsuite-resource-filename'."
  (declare (indent 1))
  `(let ((filename (flycheck-testsuite-resource-filename ,resource-file)))
     (should (file-exists-p filename))
     (with-temp-buffer
       (insert-file-contents filename t)
       (cd (file-name-directory filename))
       (rename-buffer (file-name-nondirectory filename))
       ,@body)))


;;;; Test helpers
(defmacro flycheck-testsuite-with-hook (hook-var form &rest body)
  "Set HOOK-VAR to FORM and evaluate BODY.

HOOK-VAR is a hook variable or a list thereof, which is set to
FORM before evaluating BODY.

After evaluation of BODY, set HOOK-VAR to nil."
  (declare (indent 2))
  `(let ((hooks (quote ,(if (listp hook-var) hook-var (list hook-var)))))
     (unwind-protect
          (progn
            (--each hooks (add-hook it #'(lambda () ,form)))
            ,@body)
        (--each hooks (set it nil)))))


;;;; Test environment helpers
(defun flycheck-testsuite-windows-p ()
  "Determine whether the testsuite is running on Windows."
  (memq system-type '(ms-dos windows-nt cygwin)))

(defun flycheck-testsuite-min-emacs-version-p (major &optional minor)
  "Determine whether Emacs has the required version.

Return t if Emacs is at least MAJOR.MINOR, or nil otherwise."
  (when (>= emacs-major-version major)
    (or (null minor) (>= emacs-minor-version minor))))

(defconst flycheck-testsuite-user-error-type
  (if (flycheck-testsuite-min-emacs-version-p 24 3) 'user-error 'error)
  "The `user-error' type used by Flycheck.")


;;;; Test results
(defun flycheck-testsuite-fail-unless-checkers (&rest checkers)
  "Skip the test unless all CHECKERS are present on the system.

Return `:passed' if all CHECKERS are installed, or `:failed' otherwise."
  (if (-all? 'flycheck-check-executable checkers)
      :passed
    :failed))

(defalias 'flycheck-testsuite-fail-unless-checker
  'flycheck-testsuite-fail-unless-checkers)


;;;; Checking buffers

(defvar-local flycheck-testsuite-syntax-checker-finished nil
  "Non-nil if the current checker has finished.")

(add-hook 'flycheck-after-syntax-check-hook
          (lambda () (setq flycheck-testsuite-syntax-checker-finished t)))

(defconst flycheck-testsuite-checker-wait-time 5
  "Time to wait until a checker is finished in seconds.

After this time has elapsed, the checker is considered to have
failed, and the test aborted with failure.")

(defun flycheck-testsuite-wait-for-syntax-checker ()
  "Wait until the syntax check in the current buffer is finished."
  (let ((starttime (float-time)))
    (while (and (not flycheck-testsuite-syntax-checker-finished)
                (< (- (float-time) starttime) flycheck-testsuite-checker-wait-time))
      (sleep-for 1))
    (unless (< (- (float-time) starttime) flycheck-testsuite-checker-wait-time)
      (flycheck-stop-checker)
      (error "Syntax check did not finish after %s seconds"
             flycheck-testsuite-checker-wait-time)))
  (setq flycheck-testsuite-syntax-checker-finished nil))

(defun flycheck-testsuite-disable-checkers (&rest checkers)
  "Disable all CHECKERS for the current buffer.

Each argument is a syntax checker symbol to be disabled for the
current buffer.

Turn `flycheck-checkers' into a buffer-local variable and remove
all CHECKERS from its definition."
  (set (make-local-variable 'flycheck-checkers)
       (--remove (memq it checkers) flycheck-checkers)))

(defun flycheck-testsuite-buffer-sync ()
  "Check the current buffer synchronously."
  (setq flycheck-testsuite-syntax-checker-finished nil)
  (should (not (flycheck-running-p)))
  (flycheck-mode)                       ; This will only start a deferred check,
  (flycheck-buffer)                     ; so we need an explicit manual check
  ;; After starting the check, the checker should either be running now, or
  ;; already be finished (if it was fast).
  (should (or flycheck-current-process
              flycheck-testsuite-syntax-checker-finished))
  ;; Also there should be no deferred check pending anymore
  (should-not (flycheck-deferred-check-p))
  (flycheck-testsuite-wait-for-syntax-checker))

(defun flycheck-testsuite-ensure-clear ()
  "Clear the current buffer.

Raise an assertion error if the buffer is not clear afterwards."
  (flycheck-clear)
  (should (not flycheck-current-errors))
  (should (not (--any? (overlay-get it 'flycheck-overlay)
                       (overlays-in (point-min) (point-max))))))


;;;; Test predicates
(defun flycheck-testsuite-should-overlay (overlay error)
  "Test that OVERLAY is in REGION and corresponds to ERROR."
  (let* ((region (flycheck-error-region error))
         (message (flycheck-error-message error))
         (level (flycheck-error-level error))
         (face (if (eq level 'warning)
                   'flycheck-warning-face
                 'flycheck-error-face))
         (category (if (eq level 'warning)
                       'flycheck-warning-overlay
                     'flycheck-error-overlay))
         (fringe-icon (if (eq level 'warning)
                          '(left-fringe question-mark flycheck-warning-face)
                        `(left-fringe ,flycheck-fringe-exclamation-mark
                                      flycheck-error-face))))
    (should overlay)
    (should (overlay-get overlay 'flycheck-overlay))
    (should (= (overlay-start overlay) (car region)))
    (should (= (overlay-end overlay) (cdr region)))
    (should (eq (overlay-get overlay 'face) face))
    (should (equal (get-char-property 0 'display
                                      (overlay-get overlay 'before-string))
                   fringe-icon))
    (should (eq (overlay-get overlay 'category) category))
    (should (equal (overlay-get overlay 'flycheck-error) error))
    (should (string= (overlay-get overlay 'help-echo) message))))

(defun flycheck-testsuite-should-error (expected-err)
  "Test that EXPECTED-ERR is an error in the current buffer.

Test that the error is contained in `flycheck-current-errors',
and that there is an overlay for this error at the correct
position.

EXPECTED-ERR is a list (LINE COLUMN MESSAGE LEVEL [NO-FILENAME]).
LINE and COLUMN are integers specifying the expected line and
column number respectively.  COLUMN may be nil to indicate that
the error has no column.  MESSAGE is a string with the expected
error message.  LEVEL is either `error' or `warning' and
indicates the expected error level.  If given and non-nil,
`NO-FILENAME' indicates that the error is expected to not have a
file name.

Signal a test failure if this error is not present."
  (let* ((no-filename (nth 4 expected-err))
         (real-error (flycheck-error-new
                      :buffer (current-buffer)
                      :filename (if no-filename nil (buffer-file-name))
                      :line (nth 0 expected-err)
                      :column (nth 1 expected-err)
                      :message (nth 2 expected-err)
                      :level (nth 3 expected-err)))
         (overlay (--first (equal (overlay-get it 'flycheck-error) real-error)
                           (flycheck-overlays-at (flycheck-error-pos real-error)))))
    (should (-contains? flycheck-current-errors real-error))
    (flycheck-testsuite-should-overlay overlay real-error)))

(defun flycheck-testsuite-should-errors (&rest errors)
  "Test that the current buffers has ERRORS.

Without ERRORS test that there are any errors in the current
buffer.

With ERRORS, test that each error in ERRORS is present in the
current buffer, and that the number of errors in the current
buffer is equal to the number of given ERRORS.

Each error in ERRORS is a list as expected by
`flycheck-testsuite-should-error'."
  (if (not errors)
      (should flycheck-current-errors)
    (dolist (err errors)
      (flycheck-testsuite-should-error err))
    (should (= (length errors) (length flycheck-current-errors)))
    (should (= (length errors)
               (length (flycheck-overlays-in (point-min) (point-max)))))))

(defun flycheck-testsuite-should-syntax-check
  (resource-file modes disabled-checkers &rest errors)
  "Test a syntax check in RESOURCE-FILE with MODES.

RESOURCE-FILE is the file to check.  MODES is a single major mode
symbol or a list thereof, specifying the major modes to syntax
check with.  DISABLED-CHECKERS is a syntax checker or a list
thereof to disable before checking the file.  ERRORS is the list
of expected errors."
  (when (symbolp modes)
    (setq modes (list modes)))
  (when (symbolp disabled-checkers)
    (setq disabled-checkers (list disabled-checkers)))
  (--each modes
    (flycheck-testsuite-with-resource-buffer resource-file
      (funcall it)
      (when disabled-checkers
        (apply #'flycheck-testsuite-disable-checkers disabled-checkers))
      (flycheck-testsuite-buffer-sync)
      (if (eq (car errors) :no-errors)
          (should-not flycheck-current-errors)
        (apply #'flycheck-testsuite-should-errors errors))
      (flycheck-testsuite-ensure-clear))))


(provide 'flycheck-testsuite)

;; Local Variables:
;; coding: utf-8
;; End:

;;; flycheck-testsuite.el ends here
