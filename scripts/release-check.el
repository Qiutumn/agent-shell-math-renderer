;;; release-check.el --- Checks to run before tagging a release -*- lexical-binding: t -*-

;; Copyright (C) 2026 Andrea Alberti

;; This file is not part of any package; it is run by hand before a release.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Run from the repository root before tagging a release:
;;
;;   emacs -Q -batch -l scripts/release-check.el
;;
;; It exits non-zero, saying why, unless:
;;
;; - agent-shell-math-renderer.el's `Package-Requires' names the newest
;;   `latex-to-svg-backend' on MELPA Stable.  A user who installed this
;;   package upgrades only this package; package.el upgrades a dependency
;;   only when it is below the required version, so a lower floor leaves
;;   them on an old backend;
;; - MELPA Stable has the `agent-shell' that `Package-Requires' names, or a
;;   newer one.  Without it, package.el cannot install this release from
;;   MELPA Stable;
;; - the newest dated section of CHANGELOG.md is the version in the
;;   `Version:' header, so the release has its section.
;;
;; It is a script, not an ERT test: it needs the network, and a new backend
;; release between this package's releases is no fault of this repository.

;;; Code:

(require 'lisp-mnt)
(require 'package)
(require 'url)

(defconst release-check-stable-archive
  "https://stable.melpa.org/packages/archive-contents"
  "MELPA Stable's list of packages and their versions.")

(defun release-check--header (file header)
  "Return HEADER of FILE, relative to the repository root."
  (with-temp-buffer
    (insert-file-contents file)
    (lm-header header)))

(defun release-check--required-version (file package)
  "Return the version of PACKAGE that FILE's `Package-Requires' names, or nil."
  (cadr (assq package (car (read-from-string
                            (release-check--header file "package-requires"))))))

(defun release-check--stable-contents ()
  "Return MELPA Stable's list of packages, as `package-archive-contents' holds it."
  (with-current-buffer (url-retrieve-synchronously release-check-stable-archive t t 60)
    (goto-char (point-min))
    (re-search-forward "\n\n")
    (prog1 (cdr (read (current-buffer)))
      (kill-buffer))))

(defun release-check--stable-version (package contents)
  "Return the version of PACKAGE in CONTENTS, as a string, or nil.
CONTENTS is what `release-check--stable-contents' returns."
  (when-let* ((entry (assq package contents)))
    (package-version-join (aref (cdr entry) 0))))

(defun release-check--changelog-latest ()
  "Return the newest dated version in CHANGELOG.md, or nil."
  (with-temp-buffer
    (insert-file-contents "CHANGELOG.md")
    (and (re-search-forward "^## \\[\\([0-9.]+\\)\\] - " nil t)
         (match-string 1))))

(let* ((version (release-check--header "agent-shell-math-renderer.el" "version"))
       (floor (release-check--required-version "agent-shell-math-renderer.el"
                                               'latex-to-svg-backend))
       (contents (release-check--stable-contents))
       (stable (release-check--stable-version 'latex-to-svg-backend contents))
       (shell-floor (release-check--required-version "agent-shell-math-renderer.el"
                                                     'agent-shell))
       (shell-stable (release-check--stable-version 'agent-shell contents))
       (changelog (release-check--changelog-latest))
       (problems '()))
  (message "Release %s" version)
  (message "  backend required by the renderer: %s; newest on MELPA Stable: %s"
           floor stable)
  (message "  agent-shell required by the renderer: %s; newest on MELPA Stable: %s"
           shell-floor shell-stable)
  (message "  newest dated CHANGELOG.md section: %s" changelog)
  (unless stable
    (push "MELPA Stable lists no latex-to-svg-backend" problems))
  (cond
   ((or (null stable) (version= floor stable)))
   ((version< floor stable)
    (push (format "agent-shell-math-renderer.el requires latex-to-svg-backend %s, \
but MELPA Stable has %s: raise the floor" floor stable)
          problems))
   (t
    (push (format "agent-shell-math-renderer.el requires latex-to-svg-backend %s, \
but MELPA Stable has %s: release the backend %s, or wait until MELPA \
Stable has built it" floor stable floor)
          problems)))
  (cond
   ((null shell-stable)
    (push "MELPA Stable lists no agent-shell" problems))
   ((version< shell-stable shell-floor)
    (push (format "agent-shell-math-renderer.el requires agent-shell %s, \
but MELPA Stable has %s: wait until MELPA Stable has built agent-shell %s"
                  shell-floor shell-stable shell-floor)
          problems)))
  (unless (equal changelog version)
    (push (format "CHANGELOG.md's newest dated section is %s, the header says %s"
                  changelog version)
          problems))
  (if (null problems)
      (message "OK: ready to tag v%s" version)
    (dolist (p (nreverse problems)) (message "FAIL: %s" p))
    (kill-emacs 1)))

;;; release-check.el ends here
