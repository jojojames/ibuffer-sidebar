;;; ibuffer-sidebar.el --- Sidebar for `ibuffer' -*- lexical-binding: t -*-

;; Copyright (C) 2018  Free Software Foundation, Inc.

;; Author: James Nguyen <james@jojojames.com>
;; Maintainer: James Nguyen <james@jojojames.com>
;; URL: https://github.com/jojojames/ibuffer-sidebar
;; Version: 0.0.1
;; Package-Requires: ((emacs "25.1"))
;; Keywords: ibuffer, files, tools
;; HomePage: https://github.com/jojojames/ibuffer-sidebar

;; This program is free software; you can redistribute it and/or modify
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
;; Provides a sidebar interface similar to `dired-sidebar', but for `ibuffer'.

;;
;; (use-package ibuffer-sidebar
;;   :bind (("C-x C-b" . ibuffer-sidebar-toggle-sidebar))
;;   :ensure nil
;;   :commands (ibuffer-sidebar-toggle-sidebar))
;;

;;; Code:
(require 'ibuffer)
(require 'face-remap)
(eval-when-compile (require 'subr-x))

(declare-function ibuffer-vc-set-filter-groups-by-vc-root "ibuffer-vc")
(declare-function ibuffer-do-sort-by-alphabetic "ibuffer")

;; Compatibility

(eval-and-compile
  (with-no-warnings
    (if (< emacs-major-version 26)
        (progn
          (defalias 'ibuffer-sidebar-if-let* #'if-let)
          (defalias 'ibuffer-sidebar-when-let* #'when-let)
          (function-put #'ibuffer-sidebar-if-let* 'lisp-indent-function 2)
          (function-put #'ibuffer-sidebar-when-let* 'lisp-indent-function 1))
      (defalias 'ibuffer-sidebar-if-let* #'if-let*)
      (defalias 'ibuffer-sidebar-when-let* #'when-let*))))

;; Customizations
(defgroup ibuffer-sidebar nil
  "A major mode leveraging `ibuffer-sidebar' to display buffers in a sidebar."
  :group 'convenience)

(defcustom ibuffer-sidebar-use-custom-modeline t
  "Show `ibuffer-sidebar' with custom modeline.

This uses format specified by `ibuffer-sidebar-mode-line-format'."
  :type 'boolean)

(defcustom ibuffer-sidebar-mode-line-format
  '("%e" mode-line-front-space
    mode-line-buffer-identification
    " "  mode-line-end-spaces)
  "Mode line format for `ibuffer-sidebar'."
  :type '(repeat sexp))

(defcustom ibuffer-sidebar-display-column-titles nil
  "Whether or not to display the column titles in sidebar."
  :type 'boolean)

(defcustom ibuffer-sidebar-display-summary nil
  "Whether or not to display summary in sidebar."
  :type 'boolean)

(defcustom ibuffer-sidebar-width 35
  "Width of the `ibuffer-sidebar' buffer."
  :type 'integer)

(defcustom ibuffer-sidebar-pop-to-sidebar-on-toggle-open t
  "Whether to jump to sidebar upon toggling open.

This is used in conjunction with `ibuffer-sidebar-toggle-sidebar'."
  :type 'boolean)

(defcustom ibuffer-sidebar-use-custom-font nil
  "Show `ibuffer-sidebar' with custom font.

This face can be customized using `ibuffer-sidebar-face'."
  :type 'boolean)

(defface ibuffer-sidebar-face
  nil
  "Face used by `ibuffer-sidebar' for custom font.

This only takes effect if `ibuffer-sidebar-use-custom-font' is true.")

(defcustom ibuffer-sidebar-display-alist '((side . left) (slot . 1))
  "Alist used in `display-buffer-in-side-window'.

e.g. (display-buffer-in-side-window buffer \\='((side . left) (slot . 1)))"
  :type 'alist)

(defcustom ibuffer-sidebar-refresh-on-special-commands t
  "Whether or not to trigger auto-revert after certain functions.

Warning: This is implemented by advising specific functions."
  :type 'boolean)

(defcustom ibuffer-sidebar-special-refresh-commands
  '((kill-buffer . 2)
    (find-file . 2)
    (delete-file . 2))
  "A list of commands that will trigger a refresh of the sidebar.

The command can be an alist with the CDR of the alist being the amount of time
to wait to refresh the sidebar after the CAR of the alist is called.

Set this to nil or set `ibuffer-sidebar-refresh-on-special-commands' to nil
to disable automatic refresh when a special command is triggered."
  :type '(repeat (choice symbol (cons symbol integer))))

(defcustom ibuffer-sidebar-name "*:Buffers:*"
  "The name of `ibuffer-sidebar' buffer."
  :type 'string)

(defcustom ibuffer-sidebar-refresh-timer 10
  "Refresh sidebar every N seconds.  If nil then do not refresh."
  :type 'integer)

(defcustom ibuffer-sidebar-formats
  '((mark " " name))
  "`ibuffer-formats' for `ibuffer-sidebar'."
  :type '(repeat (repeat sexp)))

(defcustom ibuffer-sidebar-toggle-hidden-commands
  '(balance-windows)
  "A list of commands that will hide `ibuffer-sidebar' temporarily.

When the command is triggered, `ibuffer-sidebar' will hide itself until
the command completes.

Set this to nil to disable this behavior."
  :type 'hook)

(defcustom ibuffer-sidebar-no-delete-other-windows nil
  "Whether the sidebar window is marked as no-delete-other-windows."
  :type 'boolean)

(defcustom ibuffer-sidebar-resize-on-open t
  "Whether to resize the sidebar window when opening it."
  :type 'boolean)

(defcustom ibuffer-sidebar-window-fixed 'width
  "Whether the sidebar window size is fixed.

Possible values: nil, `width', `height'."
  :type '(choice (const :tag "Not fixed" nil)
                 (const :tag "Fixed width" width)
                 (const :tag "Fixed height" height)))

(defcustom ibuffer-sidebar-use-ibuffer-vc-integration t
  "Whether to integrate with `ibuffer-vc'.

When true and `ibuffer-vc' is loaded, group buffers by VC root
and sort alphabetically on sidebar open."
  :type 'boolean)

(defcustom ibuffer-sidebar-open-file-in-most-recently-used-window t
  "Whether or not to open buffers in most recently used window."
  :type 'boolean)

;; Mode

(defvar-local ibuffer-sidebar-refresh-timer-object nil
  "Timer object for `ibuffer-sidebar' auto-refresh.")

(defvar ibuffer-sidebar-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'ibuffer-sidebar-visit-buffer)
    map)
  "Keymap used for symbol `ibuffer-sidebar-mode'.")

(define-derived-mode ibuffer-sidebar-mode ibuffer-mode
  "Ibuffer-sidebar"
  "A major mode that puts `ibuffer' in a sidebar."
  :group 'ibuffer-sidebar
  (let ((inhibit-read-only t))
    (setq window-size-fixed ibuffer-sidebar-window-fixed)

    (when ibuffer-sidebar-use-custom-font
      (ibuffer-sidebar-set-font))

    ;; Remove column titles.
    (unless ibuffer-sidebar-display-column-titles
      (advice-add 'ibuffer-update-title-and-summary
                  :after #'ibuffer-sidebar-remove-column-headings))

    ;; Hide summary.
    (unless ibuffer-sidebar-display-summary
      (setq-local ibuffer-display-summary nil))

    ;; Set default format to be minimal.
    (setq-local ibuffer-formats (append ibuffer-formats ibuffer-sidebar-formats))
    (setq-local ibuffer-current-format (1- (length ibuffer-formats)))
    (ibuffer-update-format)
    (ibuffer-sidebar-maybe-setup-vc)
    (ibuffer-redisplay t)

    ;; Set up refresh on timer.
    (when ibuffer-sidebar-refresh-timer
      (setq ibuffer-sidebar-refresh-timer-object
            (run-with-idle-timer
             ibuffer-sidebar-refresh-timer
             1
             #'ibuffer-sidebar-refresh-buffer))
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (when (timerp ibuffer-sidebar-refresh-timer-object)
                    (cancel-timer ibuffer-sidebar-refresh-timer-object)))
                nil t))

    ;; Set up refresh on special commands.
    (when ibuffer-sidebar-refresh-on-special-commands
      (mapc
       (lambda (x)
         (if (consp x)
             (let ((command (car x))
                   (delay (cdr x)))
               (advice-add
                command
                :after
                (defalias (intern (format "ibuffer-sidebar-refresh-after-%S" command))
                  (function
                   (lambda (&rest _)
                     (let ((timer-symbol
                            (intern
                             (format
                              "ibuffer-sidebar-refresh-%S-timer" command))))
                       (when (and (boundp timer-symbol)
                                  (timerp (symbol-value timer-symbol)))
                         (cancel-timer (symbol-value timer-symbol)))
                       (setf
                        (symbol-value timer-symbol)
                        (run-with-idle-timer
                         delay
                         nil
                         #'ibuffer-sidebar-refresh-buffer))))))))
           (advice-add x :after #'ibuffer-sidebar-refresh-buffer)))
       ibuffer-sidebar-special-refresh-commands))

    (when ibuffer-sidebar-toggle-hidden-commands
      (mapc
       (lambda (x)
         (advice-add x :around #'ibuffer-sidebar-advice-hide-temporarily))
       ibuffer-sidebar-toggle-hidden-commands))

    (when ibuffer-sidebar-use-custom-modeline
      (ibuffer-sidebar-set-mode-line))))

;; User Interface

;;;###autoload
(defun ibuffer-sidebar-toggle-sidebar ()
  "Toggle the `ibuffer-sidebar' window."
  (interactive)
  (if (ibuffer-sidebar-showing-sidebar-p)
      (ibuffer-sidebar-hide-sidebar)
    (ibuffer-sidebar-show-sidebar)
    (when ibuffer-sidebar-pop-to-sidebar-on-toggle-open
      (pop-to-buffer (ibuffer-sidebar-buffer)))))

;;;###autoload
(defun ibuffer-sidebar-show-sidebar ()
  "Show sidebar with `ibuffer'."
  (interactive)
  (let ((buffer (ibuffer-sidebar-get-or-create-buffer)))
    (display-buffer-in-side-window buffer ibuffer-sidebar-display-alist)
    (let ((window (get-buffer-window buffer)))
      (set-window-dedicated-p window t)
      (when ibuffer-sidebar-no-delete-other-windows
        (set-window-parameter window 'no-delete-other-windows t))
      (when ibuffer-sidebar-resize-on-open
        (with-selected-window window
          (let ((window-size-fixed))
            (ibuffer-sidebar-set-width ibuffer-sidebar-width)))))
    (ibuffer-sidebar-update-state buffer)))

;;;###autoload
(defun ibuffer-sidebar-hide-sidebar ()
  "Hide `ibuffer-sidebar' in selected frame."
  (ibuffer-sidebar-when-let* ((buffer (ibuffer-sidebar-buffer)))
    (delete-window (get-buffer-window buffer))
    (ibuffer-sidebar-update-state nil)))

;; Helpers

(defun ibuffer-sidebar-maybe-setup-vc ()
  "Maybe set up `ibuffer-vc'."
  (when ibuffer-sidebar-use-ibuffer-vc-integration
    (with-eval-after-load 'ibuffer-vc
      (let ((inhibit-message t))
        (ibuffer-vc-set-filter-groups-by-vc-root))
      (unless (eq ibuffer-sorting-mode 'alphabetic)
        (ibuffer-do-sort-by-alphabetic)))))

(defun ibuffer-sidebar-showing-sidebar-p (&optional f)
  "Return whether F or `selected-frame' is showing `ibuffer-sidebar'.

Check if F or `selected-frame' contains a sidebar and return corresponding
buffer if buffer has a window attached to it."
  (ibuffer-sidebar-if-let* ((buffer (ibuffer-sidebar-buffer f)))
      (get-buffer-window buffer)
    nil))

(defun ibuffer-sidebar-get-or-create-buffer ()
  "Get or create a `ibuffer-sidebar' buffer."
  (let ((name ibuffer-sidebar-name))
    (ibuffer-sidebar-if-let* ((existing-buffer (get-buffer name)))
        existing-buffer
      (let ((new-buffer (generate-new-buffer name)))
        (with-current-buffer new-buffer
          (ibuffer-sidebar-setup))
        new-buffer))))

(defun ibuffer-sidebar-setup ()
  "Bootstrap `ibuffer-sidebar'.

Sets up both `ibuffer' and `ibuffer-sidebar'."
  (ibuffer-mode)
  (ibuffer-update nil)
  (run-hooks 'ibuffer-hook)
  (ibuffer-sidebar-mode))

(defun ibuffer-sidebar-buffer (&optional _frame)
  "Return the current sidebar buffer using `window-list'."
  (if-let* ((windows (seq-filter
                      (lambda (w)
                        (with-current-buffer (window-buffer w)
                          (eq major-mode 'ibuffer-sidebar-mode)))
                      (window-list)))
            (buffer (window-buffer (car windows))))
      buffer
    nil))

(defun ibuffer-sidebar-update-state (buffer &optional f)
  "Update current state with BUFFER for sidebar in F or selected frame."
  (let ((frame (or f (selected-frame))))
    (set-frame-parameter frame 'ibuffer-sidebar buffer)))

(defun ibuffer-sidebar-refresh-buffer (&rest _)
  "Refresh sidebar buffer."
  (ibuffer-sidebar-when-let* ((sidebar (ibuffer-sidebar-buffer))
                              (window (get-buffer-window sidebar)))
    (with-selected-window window
      (ibuffer-update nil t)
      (ibuffer-sidebar-maybe-setup-vc))))

;; UI

(defun ibuffer-sidebar-remove-column-headings (&rest _args)
  "Function ran after `ibuffer-update-title-and-summary' that remove headings.

F should be function `ibuffer-update-title-and-summary'.
ARGS are args for `ibuffer-update-title-and-summary'."
  (when (and (bound-and-true-p ibuffer-sidebar-mode)
             (not ibuffer-sidebar-display-column-titles))
    (with-current-buffer (current-buffer)
      (goto-char 1)
      (search-forward "-\n" nil t)
      (delete-region 1 (point))
      (let ((window-min-height 1))
        (shrink-window-if-larger-than-buffer)))))

(defun ibuffer-sidebar-set-width (width)
  "Set the width of the buffer to WIDTH when it is created."
  ;; Copied from `treemacs--set-width' as well as `neotree'.
  (unless (one-window-p)
    (let ((window-size-fixed)
          (w (max width window-min-width)))
      (cond
       ((> (window-width) w)
        (shrink-window-horizontally  (- (window-width) w)))
       ((< (window-width) w)
        (enlarge-window-horizontally (- w (window-width))))))))

(defun ibuffer-sidebar-set-font ()
  "Customize font in `ibuffer-sidebar'.

Set font to a variable width (proportional) in the current buffer."
  (interactive)
  (setq-local buffer-face-mode-face 'ibuffer-sidebar-face)
  (buffer-face-mode))

(defun ibuffer-sidebar-set-mode-line ()
  "Customize modeline in `ibuffer-sidebar'."
  (setq mode-line-format ibuffer-sidebar-mode-line-format))

;;;###autoload
(defun ibuffer-sidebar-jump-to-sidebar ()
  "Jump to `ibuffer-sidebar' buffer if it is showing.

If it's not showing, act as `ibuffer-sidebar-toggle-sidebar'."
  (interactive)
  (if (ibuffer-sidebar-showing-sidebar-p)
      (select-window
       (get-buffer-window (ibuffer-sidebar-buffer)))
    (call-interactively #'ibuffer-sidebar-toggle-sidebar)))

(defun ibuffer-sidebar-visit-buffer ()
  "Visit the buffer at point, selecting the appropriate window."
  (interactive)
  (ibuffer-sidebar-when-let* ((buf (ibuffer-current-buffer t)))
    (select-window
     (if ibuffer-sidebar-open-file-in-most-recently-used-window
         (get-mru-window)
       (next-window)))
    (switch-to-buffer buf)))

(defun ibuffer-sidebar-advice-hide-temporarily (f &rest args)
  "Hide the sidebar before executing F with ARGS, then restore it."
  (if (not (ibuffer-sidebar-showing-sidebar-p))
      (apply f args)
    (ibuffer-sidebar-hide-sidebar)
    (apply f args)
    (ibuffer-sidebar-show-sidebar)))

(provide 'ibuffer-sidebar)
;;; ibuffer-sidebar.el ends here
