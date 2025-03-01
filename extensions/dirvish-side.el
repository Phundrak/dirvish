;;; dirvish-side.el --- Toggle Dirvish in side window like treemacs -*- lexical-binding: t -*-

;; Copyright (C) 2021-2022 Alex Lu
;; Author : Alex Lu <https://github.com/alexluigit>
;; Version: 1.9.23
;; Keywords: files, convenience
;; Homepage: https://github.com/alexluigit/dirvish
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Toggle Dirvish in side window like treemacs.

;;; Code:

(require 'dirvish-subtree)

(defcustom dirvish-side-display-alist
  '((side . left) (slot . -1) (window-width . 0.2))
  "Display alist for `dirvish-side' window."
  :group 'dirvish :type 'alist)

(defcustom dirvish-side-window-parameters '((no-delete-other-windows . t))
  "Window parameters for `dirvish-side' window."
  :group 'dirvish :type 'alist)

(defcustom dirvish-side-open-file-window-function
  (lambda () (get-mru-window nil nil t))
  "A function that returns a window for the `find-file' buffer.
This function is called before opening files in a `dirvish-side'
session.  For example, if you have `ace-window' installed, you
can set it to `ace-select-window', which prompts you for a target
window to place the file buffer.  Note that if this value is
`selected-window', the session closes after opening a file."
  :group 'dirvish :type 'function)

(defcustom dirvish-side-follow-buffer-file 'expand
  "Whether to follow current buffer's filename.
The valid value are:
- nil:        Do not follow the buffer file when reopen the side sessions
- t:          Go to file's directory and select it
- \\='expand: Go to file's project root and expand all subtrees until file"
  :group 'dirvish
  :type '(choice (const :tag "Do not follow the buffer file" nil)
                 (const :tag "Go to file's directory and select it" t)
                 (const :tag "Go to file's project root and expand subtrees" expand)))

(defcustom dirvish-side-follow-project-switch t
  "Whether visible side session update index on project switch.
If this variable is non-nil, the visible `dirvish-side' session
will visit the latest `project-root' after executing
`project-switch-project' or `projectile-switch-project'."
  :group 'dirvish :type 'boolean
  :set
  (lambda (key enabled)
    (set key enabled)
    (if enabled
        (progn
          (and (fboundp 'project-switch-project)
               (advice-add 'project-switch-project :after #'dirvish-side--auto-jump))
          (add-hook 'projectile-after-switch-project-hook #'dirvish-side--auto-jump))
      (and (fboundp 'project-switch-project)
           (advice-remove 'project-switch-project #'dirvish-side--auto-jump))
      (remove-hook 'projectile-after-switch-project-hook #'dirvish-side--auto-jump))))

(defconst dirvish-side-header (dirvish--mode-line-fmt-setter '(project) nil t))

(defun dirvish-side-on-file-open (dv)
  "Called before opening a file in Dirvish-side session DV."
  (unless (dv-layout dv)
    (select-window (funcall dirvish-side-open-file-window-function))))

(defun dirvish-side-winconf-change-h ()
  "Adjust width of side window on window configuration change."
  (let ((dv (dirvish-curr))
        window-size-fixed window-configuration-change-hook)
    (unless (dv-layout dv)
      (window--display-buffer (window-buffer) (get-buffer-window)
                              'reuse dirvish-side-display-alist))))

(defun dirvish-side-root-window-fn ()
  "Create root window according to `dirvish-side-display-alist'."
  (let ((win (display-buffer-in-side-window
              (dirvish--util-buffer) dirvish-side-display-alist)))
    (cl-loop for (key . value) in dirvish-side-window-parameters
             do (set-window-parameter win key value))
    (select-window win)))

(defun dirvish-side--session-visible-p ()
  "Return the root window of visible side session."
  (cl-loop
   for w in (window-list)
   for b = (window-buffer w)
   for dv = (with-current-buffer b (dirvish-curr))
   thereis (and dv (eq 'side (dv-type dv)) w)))

(defun dirvish-side--auto-jump (&optional dir)
  "Visit DIR in current visible `dirvish-side' session."
  (setq dir (dirvish--get-project-root dir))
  (when-let ((win (dirvish-side--session-visible-p))
             (file buffer-file-name))
    (with-selected-window win
      (when dir (dirvish-find-entry-ad dir))
      (dirvish-prop :cus-header 'dirvish-side-header)
      (if (eq dirvish-side-follow-buffer-file 'expand)
          (dirvish-subtree-expand-to file)
        (dired-goto-file file))
      (dirvish--setup-mode-line (dv-layout (dirvish-curr)))
      (dirvish-update-body-h))))

(defun dirvish-side--new (path)
  "Open a side session in PATH."
  (let ((bname buffer-file-name)
        (dv (or (dirvish--reuse-session path nil 'side)
                (dirvish-new
                  :type 'side :path path
                  :root-window-fn #'dirvish-side-root-window-fn
                  :on-file-open #'dirvish-side-on-file-open
                  :on-winconf-change #'dirvish-side-winconf-change-h))))
    (with-selected-window (dv-root-window dv)
      (cond ((not bname) nil)
            ((eq dirvish-side-follow-buffer-file 'expand)
             (dirvish-subtree-expand-to bname))
            (dirvish-side-follow-buffer-file
             (dired-goto-file bname)))
      (dirvish-prop :cus-header 'dirvish-side-header)
      (dirvish-update-body-h))))

(dirvish-define-mode-line project
  "Return a string showing current project."
  (let ((project (dirvish--get-project-root))
        (face (if (dirvish--window-selected-p dv) 'dired-header 'shadow)))
    (if project
        (setq project (file-name-base (directory-file-name project)))
      (setq project "-"))
    (format " %s %s"
            (propertize "Project:" 'face face)
            (propertize project 'face 'font-lock-string-face))))

;;;###autoload
(defun dirvish-side (&optional path)
  "Toggle a Dirvish session at the side window.

- If the current window is a side session window, hide it.
- If a side session is visible, select it.
- If a side session exists but is not visible, show it.
- If there is no side session exists,create a new one with PATH.

If called with \\[universal-arguments], prompt for PATH,
otherwise it defaults to `project-current'."
  (interactive (list (and current-prefix-arg
                          (read-directory-name "Open sidetree: "))))
  (let ((fullframep (when-let ((dv (dirvish-curr))) (dv-layout dv)))
        (visible (dirvish-side--session-visible-p))
        (path (or path (dirvish--get-project-root) default-directory)))
    (cond (fullframep (user-error "Can not create side session here"))
          ((eq visible (selected-window))
           (let ((dirvish-reuse-session t)) (dirvish-quit)))
          (visible (select-window visible))
          (t (dirvish-side--new path)))))

(provide 'dirvish-side)
;;; dirvish-side.el ends here
