;;; stock-charts.el --- 株式チャートブラウザ -*- lexical-binding: t; -*-

;;; Commentary:
;; stock-charts/meigaralist.txt に記載された
;; テーマ・銘柄コードに基づき、楽天証券・株ドラゴンのチャート画像を表示するビューア。
;;
;; 主な機能:
;;   ・ウィンドウ幅に応じたグリッドレイアウト (2列・3列・4列...)
;;   ・株ドラゴン（KabuDragon）の価格帯別出来高チャート対応 (v キーで切り替え)
;;   ・時間軸タブ (15分足 / 日足 / 週足 / 月足)。クリックまたは [ / ] キーで切り替え
;;   ・クリックで大画面チャートを表示 (大画面でも v で切り替え可能)
;;   ・取得/表示に失敗した画像は非表示にする (壊れた画像アイコンを表示しない)
;;   ・大画面モードのまま n / p で前後の銘柄に切り替え
;;   ・Imenu 対応 (i / M-g i キー、Ilist / imenu-list と連動)
;;   ・e キーで銘柄リストを編集 (保存時にチャートへ反映し、銘柄名を補完)
;;   ・東証全銘柄マスタによる、コードからの銘柄名の補完
;;   ・F1 / h キーで操作ヘルプを表示
;;
;; 使い方:
;;   M-x stock-charts または M-x my/stock-chart-open で起動

;;; Code:

(require 'cl-lib)
(require 'imenu)

(defgroup my/stock-chart nil
  "株式チャートブラウザの設定。"
  :group 'tools)

(defgroup stock-charts nil
  "株式チャートブラウザの設定。"
  :group 'tools)

;; ── テーマ連動型フェイス定義 (ダーク/ライト背景両対応) ──

(defface my/stock-chart-title
  '((((background dark)) :foreground "#38c9e8" :weight bold :height 1.2)
    (t                   :foreground "#0284c7" :weight bold :height 1.2))
  "バッファのメインタイトル用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-detail-title
  '((((background dark)) :foreground "#38c9e8" :weight bold :height 1.3)
    (t                   :foreground "#0284c7" :weight bold :height 1.3))
  "大画面詳細表示のタイトル用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-theme-header
  '((((background dark)) :foreground "#3ddc84" :weight bold :height 1.1)
    (t                   :foreground "#15803d" :weight bold :height 1.1))
  "テーマ見出し用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-stock-label
  '((((background dark)) :foreground "#f0f4ff" :weight bold)
    (t                   :foreground "#0f172a" :weight bold))
  "銘柄コード・名称ラベル用フェイス（ライト背景での白文字化を防止）。"
  :group 'my/stock-chart)

(defface my/stock-chart-back-button
  '((((background dark)) :foreground "#ffffff" :background "#c62828" :weight bold)
    (t                   :foreground "#ffffff" :background "#d32f2f" :weight bold))
  "大画面モードの「一覧に戻る」ボタン用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-link-button
  '((((background dark)) :foreground "#93c5fd" :background "#1e293b" :weight bold)
    (t                   :foreground "#0369a1" :background "#e0f2fe" :weight bold))
  "外部リンク（Yahoo! / 空売り.net）ボタン用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-tab-list-inactive
  '((((background dark)) :foreground "#ce93d8" :background "#2a153d" :weight bold)
    (t                   :foreground "#4a148c" :background "#f3e5f5" :weight bold))
  "非選択時のリストタブ用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-tab-type-inactive
  '((((background dark)) :foreground "#81c784" :background "#1b2e1b" :weight bold)
    (t                   :foreground "#1b5e20" :background "#e8f5e9" :weight bold))
  "非選択時の形式タブ用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-tab-interval-inactive
  '((((background dark)) :foreground "#7aa2f7" :background "#1f2335" :weight bold)
    (t                   :foreground "#0d47a1" :background "#e3f2fd" :weight bold))
  "非選択時の時間軸タブ用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-btn-save
  '((((background dark)) :foreground "#ffffff" :background "#15803d" :weight bold)
    (t                   :foreground "#ffffff" :background "#16a34a" :weight bold))
  "リスト編集の保存ボタン用フェイス。"
  :group 'my/stock-chart)

(defface my/stock-chart-btn-cancel
  '((((background dark)) :foreground "#ffffff" :background "#b91c1c" :weight bold)
    (t                   :foreground "#ffffff" :background "#dc2626" :weight bold))
  "リスト編集のキャンセルボタン用フェイス。"
  :group 'my/stock-chart)

(defconst my/stock-chart-pkg-dir
  (file-name-directory (or load-file-name
                           buffer-file-name
                           (locate-library "stock-charts")
                           (locate-library "my-stock-chart")
                           (and (boundp 'user-emacs-directory)
                                (expand-file-name "lisp/stock-charts/" user-emacs-directory))
                           (and (boundp 'user-emacs-directory)
                                (expand-file-name "site-lisp/stock-charts/" user-emacs-directory))
                           default-directory))
  "stock-charts パッケージが配置されているディレクトリ。")

(defconst stock-charts-pkg-dir my/stock-chart-pkg-dir
  "stock-charts パッケージが配置されているディレクトリ。")

(defcustom my/stock-chart-dir
  (or (getenv "STOCK_CHART_DIR")
      (let ((pkg-stocks (expand-file-name "stock-charts/" my/stock-chart-pkg-dir))
            (emacs-stocks (let ((base (if (boundp 'user-emacs-directory)
                                          user-emacs-directory
                                        "~/.emacs.d/")))
                            (expand-file-name "stock-charts/" base))))
        (cond
         ((file-directory-p pkg-stocks) pkg-stocks)
         ((file-directory-p emacs-stocks) emacs-stocks)
         (t pkg-stocks))))
  "銘柄リストファイルが保存されるディレクトリ。
環境変数 `STOCK_CHART_DIR` が設定されていればそれを最優先します。"
  :type 'directory
  :group 'my/stock-chart)

(defcustom my/stock-chart-list-file
  (expand-file-name "meigaralist.txt" my/stock-chart-dir)
  "デフォルトの銘柄リストファイルパス（後方互換用）。"
  :type 'file
  :group 'my/stock-chart)

(defvar my/stock-chart-current-list-file nil
  "現在選択中の銘柄リストファイルパス。nil の場合は slot 1 が使われる。")

(defcustom my/stock-chart-edit-window-position 'right
  "リスト編集ウィンドウの表示位置 ('right, 'below, 'same-window)。
'right: ウィンドウの右側に縦分割で表示（画面幅110桁以上の場合は右側40%幅、未満なら下部表示）
'below: ウィンドウの下部に横分割で表示
'same-window: 現在のウィンドウで表示"
  :type '(choice (const :tag "右側に分割表示 (チャートと見比べ可能)" right)
                 (const :tag "下部に分割表示" below)
                 (const :tag "同じウィンドウで表示" same-window))
  :group 'my/stock-chart)

(defcustom my/stock-chart-cache-dir
  (or (getenv "STOCK_CHART_CACHE_DIR")
      (let ((base (if (boundp 'user-emacs-directory)
                      user-emacs-directory
                    "~/.emacs.d/")))
        (expand-file-name ".cache/stock-charts/" base)))
  "チャート画像のキャッシュ保存先ディレクトリ。
環境変数 `STOCK_CHART_CACHE_DIR` が設定されていればそれを最優先します。"
  :type 'directory
  :group 'my/stock-chart)

(defcustom my/stock-chart-cache-ttl (* 12 3600)
  "チャート画像キャッシュの有効期間（秒）。デフォルトは12時間 (43200秒)。
この秒数が経過したキャッシュ画像は自動的に再取得（ダウンロード）されます。
nil に設定すると無期限（g キーでのみ再取得）になります。"
  :type '(choice (integer :tag "秒数 (例: 43200 = 12時間)")
                 (const :tag "無期限 (g キーでのみ更新)" nil))
  :group 'my/stock-chart)

(defconst my/stock-chart-intervals '(15min daily weekly monthly)
  "利用可能な時間軸のリスト。")

(defvar my/stock-chart-current-interval 'daily
  "現在の足種 ('daily, '15min, 'weekly, 'monthly)。")

(defvar my/stock-chart-current-type 'rakuten
  "現在のチャート形式 ('rakuten: 楽天通常, 'dragon: 株ドラゴン価格帯別出来高)。")

(defvar-local my/stock-chart--last-window-width nil
  "前回描画時のウィンドウ幅 (px)。")

(defvar-local my/stock-chart--resize-timer nil
  "リサイズ追従用のディバウンスタイマー。")

(defvar-local my/stock-chart--imenu-index nil
  "Imenu 用の階層インデックスキャッシュ。")

;; ── 楽天エラー画像テンプレート ──

(defun my/stock-chart--rakuten-error-template-file ()
  "楽天証券のエラー画像テンプレートのパスを返す。"
  (expand-file-name "rakuten_error_template.gif" my/stock-chart-cache-dir))

(defun my/stock-chart--ensure-rakuten-error-template ()
  "エラー画像テンプレートが存在しなければ自動取得して保管する。"
  (let ((tpl (my/stock-chart--rakuten-error-template-file)))
    (unless (file-exists-p tpl)
      (unless (file-directory-p my/stock-chart-cache-dir)
        (make-directory my/stock-chart-cache-dir t))
      (let ((curl-exe (if (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe" (or (executable-find "curl") "curl"))))
        (call-process curl-exe nil nil nil "-s" "-L" "--ssl-no-revoke"
                      "-o" (replace-regexp-in-string "/" "\\\\" tpl)
                      "https://www.trkd-asia.com/rakutensec/common/genChart.jsp?sym=__ERROR_CHECK__.T&mode=2&int=5&per=4&toparg=5,25,75&top=4&bottom=2&style=1&width=320&height=160&tpoint=checked")))))

(defun my/stock-chart--file-equal-p (f1 f2)
  "2つのファイルがバイナリレベルで一致しているか判定する。"
  (and (file-exists-p f1)
       (file-exists-p f2)
       (= (file-attribute-size (file-attributes f1))
          (file-attribute-size (file-attributes f2)))
       (with-temp-buffer
         (set-buffer-multibyte nil)
         (insert-file-contents-literally f1)
         (let ((c1 (buffer-string)))
           (erase-buffer)
           (insert-file-contents-literally f2)
           (string= c1 (buffer-string))))))

;; ── 画像ファイルの正常性検証 ──

(defun my/stock-chart--valid-image-p (file-path)
  "FILE-PATH が正常な画像ファイルであるかを厳密に検証する。
保管されている楽天エラー画像と一致するものや、極小ファイル、HTMLエラー等は削除して nil を返す。"
  (and file-path
       (file-exists-p file-path)
       (let ((size (file-attribute-size (file-attributes file-path)))
             (tpl (my/stock-chart--rakuten-error-template-file)))
         (my/stock-chart--ensure-rakuten-error-template)
         (cond
          ;; 500B以下（空ファイルや株ドラゴンの88Bエラー等）
          ((or (null size) (<= size 500))
           (when (file-exists-p file-path)
             (delete-file file-path))
           nil)
          ;; 株ドラゴン関連で元画像が 500B 以下（透明エラー）の場合、そのサムネイル/大画面も削除
          ((and (string-match "\\(.*\\)_dragon_\\(thumb\\|large\\)\\.png$" file-path)
                (let ((raw-file (format "%s_dragon.png" (match-string 1 file-path))))
                  (and (file-exists-p raw-file)
                       (let ((rsize (file-attribute-size (file-attributes raw-file))))
                         (or (null rsize) (<= rsize 500))))))
           (when (file-exists-p file-path)
             (delete-file file-path))
           nil)
          ;; 楽天エラー画像テンプレートと一致
          ((my/stock-chart--file-equal-p file-path tpl)
           (when (file-exists-p file-path)
             (delete-file file-path))
           nil)
          ;; 画像フォーマット判定 (GIF, PNG など表示可能か)
          (t
           (condition-case nil
               (let ((type (image-type-from-file-header file-path)))
                 (if (and type (image-type-available-p type))
                     t
                   (when (file-exists-p file-path)
                     (delete-file file-path))
                   nil))
             (error nil)))))))

(defun my/stock-chart--cache-expired-p (file-path)
  "FILE-PATH のキャッシュが有効期限（`my/stock-chart-cache-ttl`）を過ぎているか判定する。
ファイルが存在しない場合は nil を返す（未取得扱いは valid-image-p 等で判定）。"
  (and my/stock-chart-cache-ttl
       file-path
       (file-exists-p file-path)
       (let* ((attrs (file-attributes file-path))
              (mtime (file-attribute-modification-time attrs))
              (elapsed (float-time (time-subtract (current-time) mtime))))
         (> elapsed my/stock-chart-cache-ttl))))

;; ── 銘柄リスト管理 (1〜9スロット ＆ 存在するファイル自動検出) ──

(defun my/stock-chart--ensure-dirs ()
  "必要なディレクトリ (stock-charts/ および .cache/stock-charts/) を作成する。"
  (unless (file-directory-p my/stock-chart-dir)
    (make-directory my/stock-chart-dir t))
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t)))

(defun my/stock-chart--slot-file (index)
  "スロット番号 INDEX (1〜9) のファイルパスを返す。
1 の場合、meigaralist1.txt が存在すればそれを、無ければ meigaralist.txt を返す。"
  (my/stock-chart--ensure-dirs)
  (let ((dir (file-name-as-directory (expand-file-name my/stock-chart-dir))))
    (if (= index 1)
        (let ((f1 (expand-file-name "meigaralist1.txt" dir))
              (f0 (expand-file-name "meigaralist.txt" dir)))
          (if (file-exists-p f1) f1 f0))
      (expand-file-name (format "meigaralist%d.txt" index) dir))))

(defun my/stock-chart--existing-slots ()
  "実際にファイルが存在するスロットの ((INDEX . FILE-PATH) ...) リストを返す (1〜9)。"
  (my/stock-chart--ensure-dirs)
  (let ((slots nil))
    (dotimes (i 9)
      (let* ((idx (1+ i))
             (f (my/stock-chart--slot-file idx)))
        (when (file-exists-p f)
          (push (cons idx f) slots))))
    (nreverse slots)))

(defun my/stock-chart--ensure-default-list ()
  "meigaralist.txt が存在しない場合、初期サンプルを作成する。"
  (my/stock-chart--ensure-dirs)
  (let ((f1 (my/stock-chart--slot-file 1)))
    (unless (file-exists-p f1)
      (with-temp-file f1
        (insert "# よく見る一覧（主力テーマ）\n\n"
                "[代表銘柄]\n"
                "7203 トヨタ\n"
                "6758 ソニーG\n"
                "7974 任天堂\n"
                "9984 ソフトバンクG\n\n"
                "[半導体・ハイテク]\n"
                "8035 東京エレクトロン\n"
                "6857 アドバンテスト\n"
                "SMH 米国株ETF(SMH)\n\n"
                "[金融・高配当]\n"
                "8306 三菱UFJ\n"
                "8058 三菱商事\n"
                "9432 NTT\n")))))

(defun my/stock-chart--current-file ()
  "現在アクティブなリストファイルパスを返す。"
  (my/stock-chart--ensure-default-list)
  (if (and my/stock-chart-current-list-file
           (file-exists-p my/stock-chart-current-list-file))
      my/stock-chart-current-list-file
    (setq my/stock-chart-current-list-file (my/stock-chart--slot-file 1))))

(defun my/stock-chart--list-title (file-path &optional index)
  "ファイル先頭のコメント（# タイトル...）から表示名を取得する。無ければファイル名。"
  (let* ((fname (file-name-nondirectory file-path))
         (raw-title
          (if (file-exists-p file-path)
              (with-temp-buffer
                (insert-file-contents file-path nil 0 300)
                (goto-char (point-min))
                (if (re-search-forward "^#[ \t]*\\(.*?\\)[ \t]*$" nil t)
                    (match-string 1)
                  fname))
            fname)))
    (if index
        (format "[%d] %s" index raw-title)
      raw-title)))

(defun my/stock-chart--parse-list-file (&optional file-path)
  "銘柄リストファイルを解析し、((テーマ . ((コード . 銘柄名) ...)) ...) の形式で返す。"
  (let ((target-file (or file-path (my/stock-chart--current-file))))
    (unless (file-exists-p target-file)
      (my/stock-chart--ensure-default-list))
    (let ((result nil)
          (current-theme "未分類")
          (current-stocks nil))
      (with-temp-buffer
        (insert-file-contents target-file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (string-trim (buffer-substring-no-properties
                                    (line-beginning-position)
                                    (line-end-position)))))
            (cond
             ((or (string-empty-p line)
                  (string-prefix-p "#" line)
                  (string-prefix-p "//" line)))
             ((string-match "^\\[\\(.+\\)\\]$" line)
              (when current-stocks
                (push (cons current-theme (nreverse current-stocks)) result)
                (setq current-stocks nil))
              (setq current-theme (match-string 1 line)))
             ((string-match "^\\([0-9A-Za-z]+\\)[ \t]*\\(.*\\)$" line)
              (let* ((code (match-string 1 line))
                     (name (string-trim (match-string 2 line)))
                     (name-clean (if (string-empty-p name)
                                     (or (my/stock-chart-lookup-name code) code)
                                   name)))
                (push (cons code name-clean) current-stocks)))))
          (forward-line 1))
        (when current-stocks
          (push (cons current-theme (nreverse current-stocks)) result)))
      (nreverse result))))

(defun my/stock-chart--all-stocks (&optional file-path)
  "指定リストファイルの全銘柄 ((コード . 銘柄名) ...) フラットリストを返す。"
  (let ((data (my/stock-chart--parse-list-file file-path)))
    (cl-mapcan (lambda (group) (copy-sequence (cdr group))) data)))

(defun my/stock-chart-cycle-list (direction)
  "存在するリストファイルの間を前後にサイクル切り替えする (DIRECTION: 1 で次, -1 で前)。"
  (interactive)
  (let* ((slots (my/stock-chart--existing-slots)))
    (if (null slots)
        (message "利用可能な銘柄リストファイルが見つかりません。")
      (let* ((files (mapcar #'cdr slots))
             (curr (expand-file-name (my/stock-chart--current-file)))
             (curr-idx (cl-position curr (mapcar #'expand-file-name files) :test #'string=))
             (new-idx (if curr-idx
                          (mod (+ curr-idx direction) (length files))
                        0))
             (next-file (nth new-idx files))
             (slot-info (nth new-idx slots)))
        (setq my/stock-chart-current-list-file next-file)
        (my/stock-chart-render nil)
        (message "リストを切り替えました: %s"
                 (my/stock-chart--list-title next-file (car slot-info)))))))

(defun my/stock-chart-switch-list-by-index (index)
  "指定番号 (INDEX: 1〜9) のリストに切り替える。未作成の場合は作成を確認。"
  (interactive "nリスト番号 (1-9): ")
  (when (and (>= index 1) (<= index 9))
    (let ((file (my/stock-chart--slot-file index)))
      (if (file-exists-p file)
          (progn
            (setq my/stock-chart-current-list-file file)
            (my/stock-chart-render nil)
            (message "リストを切り替えました: %s" (my/stock-chart--list-title file index)))
        (if (y-or-n-p (format "%s が存在しません。新規作成して開きますか? "
                              (file-name-nondirectory file)))
            (progn
              (with-temp-file file
                (insert (format "# リスト%d\n\n[テーマ名]\n7203 トヨタ\n" index)))
              (setq my/stock-chart-current-list-file file)
              (my/stock-chart-render nil)
              (my/stock-chart-edit-list))
          (message "切り替えをキャンセルしました。"))))))

(defun my/stock-chart-switch-list ()
  "登録されたリスト一覧から選択して切り替える。"
  (interactive)
  (let* ((slots (my/stock-chart--existing-slots))
         (cands (mapcar (lambda (slot)
                          (let* ((idx (car slot))
                                 (f (cdr slot))
                                 (title (my/stock-chart--list-title f idx))
                                 (count (length (my/stock-chart--all-stocks f))))
                            (cons (format "%-35s (%d 銘柄)" title count) f)))
                        slots)))
    ;; 未作成スロットも選択肢の末尾に追加
    (dotimes (i 9)
      (let* ((idx (1+ i))
             (f (my/stock-chart--slot-file idx)))
        (unless (file-exists-p f)
          (push (cons (format "[%d] %s を新規作成..." idx (file-name-nondirectory f)) f)
                cands))))
    (setq cands (nreverse cands))
    (let* ((choice (completing-read "銘柄リスト切り替え: " (mapcar #'car cands) nil t))
           (target (cdr (assoc choice cands))))
      (when target
        (unless (file-exists-p target)
          (with-temp-file target
            (insert (format "# 新規リスト\n\n[テーマ名]\n7203 トヨタ\n"))))
        (setq my/stock-chart-current-list-file target)
        (my/stock-chart-render nil)
        (message "リストを切り替えました: %s" (my/stock-chart--list-title target))))))

;; ── シンボル判定と URL 生成 ──

(defun my/stock-chart--japan-stock-p (code)
  "日本株（数字コード等）かどうかを判定する。"
  (string-match-p "^[0-9]+[A-Za-z]?$" (replace-regexp-in-string "（.*）" "" code)))

(defun my/stock-chart--to-symbol (code)
  "銘柄コードを楽天証券のシンボル文字列に変換する。"
  (let ((clean-code (replace-regexp-in-string "（.*）" "" code)))
    (if (my/stock-chart--japan-stock-p clean-code)
        (concat clean-code ".T")
      clean-code)))

(defun my/stock-chart--url-param (interval)
  "足種に応じた楽天証券 API パラメータを返す。"
  (pcase interval
    ('daily   "int=5&per=4&top=4&toparg=5,25,75")
    ('15min   "int=3&per=2&top=8&toparg=")
    ('weekly  "int=6&per=9&top=4&toparg=9,13,26")
    ('monthly "int=7&per=12&top=4&toparg=6,12,24")
    (_        "int=5&per=4&top=4&toparg=5,25,75")))

(defun my/stock-chart--url (sym interval)
  "楽天証券のサムネイル用チャート画像URL (320x160px) を生成する。"
  (format "https://www.trkd-asia.com/rakutensec/common/genChart.jsp?sym=%s&mode=2&%s&bottom=2&style=1&width=320&height=160&tpoint=checked"
          sym (my/stock-chart--url-param interval)))

(defun my/stock-chart--cache-file (sym interval)
  "楽天証券サムネイル画像のキャッシュパスを返す。"
  (expand-file-name (format "%s_%s.png" sym interval) my/stock-chart-cache-dir))

(defun my/stock-chart--large-url (sym interval)
  "楽天証券の大画面用チャート画像URL (800x480px) を生成する。"
  (format "https://www.trkd-asia.com/rakutensec/common/genChart.jsp?sym=%s&mode=2&%s&bottom=2&style=1&width=800&height=480&tpoint=checked"
          sym (my/stock-chart--url-param interval)))

(defun my/stock-chart--large-cache-file (sym interval)
  "楽天証券大画面チャート画像のキャッシュパスを返す。"
  (expand-file-name (format "%s_%s_large.png" sym interval) my/stock-chart-cache-dir))

;; ── 株ドラゴン (価格帯別出来高) URL と キャッシュ ──

(defun my/stock-chart--dragon-url (code &optional interval)
  "株ドラゴンの価格帯別出来高チャート画像URLを生成する。
INTERVAL: 'daily (日足), 'weekly (週足 /a=1/), 'monthly (月足 /a=2/)。"
  (let* ((clean-code (replace-regexp-in-string "（.*）" "" code))
         (int-param (pcase interval
                      ('weekly  "/a=1/")
                      ('monthly "/a=2/")
                      (_        ""))))
    (format "https://www.kabudragon.com/chart/s=%s/volb=1%s" clean-code int-param)))

(defun my/stock-chart--dragon-raw-file (code &optional interval)
  "株ドラゴンの元画像キャッシュパス (640x241) を返す。"
  (let ((int (or interval 'daily))
        (clean (replace-regexp-in-string "（.*）" "" code)))
    (expand-file-name (format "%s_%s_dragon.png" clean int) my/stock-chart-cache-dir)))

(defun my/stock-chart--dragon-thumb-file (code &optional interval)
  "株ドラゴンのサムネイル画像パス (320x120) を返す。"
  (let ((int (or interval 'daily))
        (clean (replace-regexp-in-string "（.*）" "" code)))
    (expand-file-name (format "%s_%s_dragon_thumb.png" clean int) my/stock-chart-cache-dir)))

(defun my/stock-chart--dragon-large-file (code &optional interval)
  "株ドラゴンの大画面拡大画像パス (960x361) を返す。"
  (let ((int (or interval 'daily))
        (clean (replace-regexp-in-string "（.*）" "" code)))
    (expand-file-name (format "%s_%s_dragon_large.png" clean int) my/stock-chart-cache-dir)))

(defun my/stock-chart--dragon-cache-file (code &optional interval)
  "後方互換用: サムネイル画像パスを返す。"
  (my/stock-chart--dragon-thumb-file code interval))

(defun my/stock-chart--ensure-dragon-resized ()
  "PowerShell を使って未リサイズまたは更新された株ドラゴン画像をサムネイル(320px)と大画面(960px)に一括変換する。"
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let* ((ps1-in-pkg   (expand-file-name "resize_dragon.ps1" my/stock-chart-pkg-dir))
         (ps1-in-cache (expand-file-name "resize_dragon.ps1" my/stock-chart-cache-dir))
         (ps1-path (cond ((file-exists-p ps1-in-pkg) ps1-in-pkg)
                         ((file-exists-p ps1-in-cache) ps1-in-cache)
                         (t ps1-in-cache))))
    (unless (file-exists-p ps1-path)
      (let ((ps1-content
             (concat
              "param([string]$dir)\n"
              "Add-Type -AssemblyName System.Drawing\n"
              "$files = Get-ChildItem \"$dir\\*_dragon.png\"\n"
              "foreach ($f in $files) {\n"
              "    $base = $f.BaseName\n"
              "    if ($base -like \"*_thumb\" -or $base -like \"*_large\") { continue }\n"
              "    $thumb = \"$dir\\$($base)_thumb.png\"\n"
              "    $large = \"$dir\\$($base)_large.png\"\n"
              "    if ($f.Length -le 500) {\n"
              "        if (Test-Path $thumb) { Remove-Item $thumb -Force }\n"
              "        if (Test-Path $large) { Remove-Item $large -Force }\n"
              "        continue\n"
              "    }\n"
              "    $needThumb = (-not (Test-Path $thumb)) -or ($f.LastWriteTime -gt (Get-Item $thumb).LastWriteTime)\n"
              "    $needLarge = (-not (Test-Path $large)) -or ($f.LastWriteTime -gt (Get-Item $large).LastWriteTime)\n"
              "    if ($needThumb -or $needLarge) {\n"
              "        try {\n"
              "            $src = [System.Drawing.Image]::FromFile($f.FullName)\n"
              "            if ($src.Width -lt 100 -or $src.Height -lt 50) {\n"
              "                $src.Dispose()\n"
              "                if (Test-Path $thumb) { Remove-Item $thumb -Force }\n"
              "                if (Test-Path $large) { Remove-Item $large -Force }\n"
              "                continue\n"
              "            }\n"
              "            if ($needThumb) {\n"
              "                $bm1 = New-Object System.Drawing.Bitmap(320, 120)\n"
              "                $g1 = [System.Drawing.Graphics]::FromImage($bm1)\n"
              "                $g1.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic\n"
              "                $g1.DrawImage($src, 0, 0, 320, 120)\n"
              "                $bm1.Save($thumb, [System.Drawing.Imaging.ImageFormat]::Png)\n"
              "                $g1.Dispose(); $bm1.Dispose()\n"
              "            }\n"
              "            if ($needLarge) {\n"
              "                $bm2 = New-Object System.Drawing.Bitmap(960, 361)\n"
              "                $g2 = [System.Drawing.Graphics]::FromImage($bm2)\n"
              "                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic\n"
              "                $g2.DrawImage($src, 0, 0, 960, 361)\n"
              "                $bm2.Save($large, [System.Drawing.Imaging.ImageFormat]::Png)\n"
              "                $g2.Dispose(); $bm2.Dispose()\n"
              "            }\n"
              "            $src.Dispose()\n"
              "        } catch {}\n"
              "    }\n"
              "}\n")))
        (with-temp-file ps1-path
          (insert ps1-content))))
    (call-process "powershell.exe" nil nil nil
                  "-NoProfile" "-ExecutionPolicy" "Bypass" "-File"
                  (replace-regexp-in-string "/" "\\\\" ps1-path)
                  (replace-regexp-in-string "/" "\\\\" my/stock-chart-cache-dir))))

;; ── 画像ダウンロード (curl) ──

(defun my/stock-chart--fetch-images (items interval &optional force)
  "ITEMS の楽天証券サムネイル画像を curl で並列ダウンロードする。"
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let ((curl-exe (if (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe" (or (executable-find "curl") "curl")))
         (args '("-s" "-L" "--ssl-no-revoke" "-A" "Mozilla/5.0" "--parallel")))
    (dolist (item items)
      (let* ((code (car item))
             (sym (my/stock-chart--to-symbol code))
             (cache-path (my/stock-chart--cache-file sym interval))
             (url (my/stock-chart--url sym interval)))
        (when (or force
                  (my/stock-chart--cache-expired-p cache-path)
                  (not (my/stock-chart--valid-image-p cache-path)))
          (setq args (append args (list "-o" (replace-regexp-in-string "/" "\\\\" cache-path) url))))))
    (when (> (length args) 6)
      (message "チャート画像を取得中 (並列ダウンロード)...")
      (apply #'call-process curl-exe nil nil nil args)
      (clear-image-cache)
      (message "チャート画像の取得完了!"))))

(defun my/stock-chart--fetch-dragon-images (items interval &optional force)
  "ITEMS の株ドラゴン価格帯別出来高画像 (INTERVAL) を curl で並列ダウンロードし、リサイズする。"
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let ((curl-exe (if (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe" (or (executable-find "curl") "curl")))
         (args '("-s" "-L" "--ssl-no-revoke" "-A" "Mozilla/5.0" "--parallel")))
    (dolist (item items)
      (let* ((code (car item)))
        (when (my/stock-chart--japan-stock-p code)
          (let ((raw-path (my/stock-chart--dragon-raw-file code interval))
                (url (my/stock-chart--dragon-url code interval)))
            (when (or force
                      (my/stock-chart--cache-expired-p raw-path)
                      (not (my/stock-chart--valid-image-p raw-path)))
              (setq args (append args (list "-o" (replace-regexp-in-string "/" "\\\\" raw-path) url))))))))
    (when (> (length args) 6)
      (message "株ドラゴンの価格帯別出来高チャート [%s] を取得中 (並列ダウンロード)..." (my/stock-chart--interval-short-name interval))
      (apply #'call-process curl-exe nil nil nil args)
      ;; ダウンロード後にサムネイルと大画面用画像を一括生成
      (my/stock-chart--ensure-dragon-resized)
      (clear-image-cache)
      (message "株ドラゴンチャートの取得完了!"))))

(defun my/stock-chart--fetch-single-large (sym interval &optional force)
  "指定銘柄の楽天大画面チャート (800x480) を同期ダウンロードする。"
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let* ((cache-path (my/stock-chart--large-cache-file sym interval))
         (curl-exe (if (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe" (or (executable-find "curl") "curl"))))
    (when (or force
              (my/stock-chart--cache-expired-p cache-path)
              (not (my/stock-chart--valid-image-p cache-path)))
      (message "大画面チャートを取得中 (%s %s)..." sym interval)
      (call-process curl-exe nil nil nil "-s" "-L" "--ssl-no-revoke" "-A" "Mozilla/5.0"
                    "-o" (replace-regexp-in-string "/" "\\\\" cache-path)
                    (my/stock-chart--large-url sym interval))
      (clear-image-cache cache-path)
      (message "大画面チャートの取得完了!"))
    cache-path))

(defun my/stock-chart--fetch-single-dragon (code &optional interval force)
  "指定銘柄の株ドラゴン価格帯別出来高チャート (INTERVAL) を取得・拡大生成し、大画面用パスを返す。"
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let* ((int (or interval 'daily))
         (raw-path (my/stock-chart--dragon-raw-file code int))
         (large-path (my/stock-chart--dragon-large-file code int))
         (curl-exe (if (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe" (or (executable-find "curl") "curl"))))
    (when (or force
              (my/stock-chart--cache-expired-p raw-path)
              (not (my/stock-chart--valid-image-p raw-path)))
      (message "株ドラゴンの価格帯別出来高を取得中 (%s %s)..." code (my/stock-chart--interval-short-name int))
      (call-process curl-exe nil nil nil "-s" "-L" "--ssl-no-revoke" "-A" "Mozilla/5.0"
                    "-o" (replace-regexp-in-string "/" "\\\\" raw-path)
                    (my/stock-chart--dragon-url code int))
      (my/stock-chart--ensure-dragon-resized)
      (clear-image-cache raw-path)
      (clear-image-cache large-path)
      (message "株ドラゴンチャートの取得完了!"))
    (if (my/stock-chart--valid-image-p large-path)
        large-path
      raw-path)))

;; ── 画像の取得と代替表示 (株ドラゴン ⇄ 楽天証券) ──

(defun my/stock-chart--resolve-thumb-image (code sym interval primary-type)
  "指定銘柄のサムネイル画像パスと、実際に使用された形式 ('rakuten または 'dragon) を解決する。
PRIMARY-TYPE で指定された形式を優先し、取得不可時はもう一方の形式で代替する。
返り値: (file-path actual-type is-fallback)"
  (let* ((dragon-available-p (and (my/stock-chart--japan-stock-p code)
                                  (not (eq interval '15min))))
         (order (if (eq primary-type 'dragon)
                    (if dragon-available-p '(dragon rakuten) '(rakuten))
                  (if dragon-available-p '(rakuten dragon) '(rakuten))))
         (chosen-file nil)
         (chosen-type nil)
         (fallback nil))
    (catch 'found
      (dolist (typ order)
        (let ((file (if (eq typ 'dragon)
                        (my/stock-chart--dragon-thumb-file code interval)
                      (my/stock-chart--cache-file sym interval))))
          (when (my/stock-chart--valid-image-p file)
            (setq chosen-file file
                  chosen-type typ
                  fallback (not (eq typ primary-type)))
            (throw 'found t)))))
    (list chosen-file chosen-type fallback)))

(defun my/stock-chart--resolve-large-image (code sym interval primary-type &optional force)
  "指定銘柄の大画面画像パスと、実際に使用された形式を解決する。
PRIMARY-TYPE を優先し、取得不可時はもう一方の形式から大画面画像を自動取得して代替する。
返り値: (file-path actual-type is-fallback)"
  (let* ((dragon-available-p (and (my/stock-chart--japan-stock-p code)
                                  (not (eq interval '15min))))
         (order (if (eq primary-type 'dragon)
                    (if dragon-available-p '(dragon rakuten) '(rakuten))
                  (if dragon-available-p '(rakuten dragon) '(rakuten))))
         (chosen-file nil)
         (chosen-type nil)
         (fallback nil))
    (catch 'found
      (dolist (typ order)
        (let ((file (if (eq typ 'dragon)
                        (my/stock-chart--fetch-single-dragon code interval force)
                      (my/stock-chart--fetch-single-large sym interval force))))
          (when (my/stock-chart--valid-image-p file)
            (setq chosen-file file
                  chosen-type typ
                  fallback (not (eq typ primary-type)))
            (throw 'found t)))))
    (list chosen-file chosen-type fallback)))

;; ── ヘッダータブ UI ──

(defun my/stock-chart--interval-name (interval)
  "足種の表示名を返す。"
  (pcase interval
    ('daily   "日足 (DAILY)")
    ('15min   "15分足 (15MIN)")
    ('weekly  "週足 (WEEKLY)")
    ('monthly "月足 (MONTHLY)")
    (_        "日足")))

(defun my/stock-chart--interval-short-name (interval)
  "足種の短縮表示名を返す。"
  (pcase interval
    ('daily   "日足")
    ('15min   "15分足")
    ('weekly  "週足")
    ('monthly "月足")
    (_        "日足")))

(defun my/stock-chart--render-list-tabs (current-file &optional is-detail)
  "存在するリストファイル (1〜9) のクリック可能タブUI文字列を生成する。"
  (let* ((slots (my/stock-chart--existing-slots))
         (curr-exp (expand-file-name (or current-file (my/stock-chart--current-file))))
         (res " リスト: "))
    (dolist (slot slots)
      (let* ((idx (car slot))
             (f (cdr slot))
             (active (string= (expand-file-name f) curr-exp))
             (title (my/stock-chart--list-title f idx))
             (label (if active (format " 【 %s 】 " title) (format " [ %s ] " title)))
             (map (make-sparse-keymap)))
        (define-key map [mouse-1] (lambda () (interactive) (my/stock-chart-switch-list-by-index idx)))
        (setq res
              (concat res
                      (if active
                          (propertize label
                                      'face '(:weight bold :foreground "#ffffff" :background "#6a1b9a")
                                      'mouse-face '(:background "#8e24aa" :foreground "#ffffff")
                                      'local-map map
                                      'help-echo (format "現在表示中: %s" title))
                        (propertize label
                                    'face 'my/stock-chart-tab-list-inactive
                                    'mouse-face '(:background "#8e24aa" :foreground "#ffffff")
                                    'local-map map
                                    'help-echo (format "クリックして「%s」に切り替え" title)))
                      "  "))))
    (concat res " (切替: l または ( / ) または M-1〜9)\n")))

(defun my/stock-chart--render-type-tabs (current-type &optional is-detail)
  "チャート形式のクリック可能タブUIを生成する。"
  (let* ((types '((rakuten "楽天 (通常)" "v")
                  (dragon  "株ドラゴン (価格帯別出来高)" "v")))
         (res " 形式:   "))
    (dolist (item types)
      (let* ((sym (nth 0 item))
             (label (nth 1 item))
             (active (eq sym current-type))
             (label-str (if active (format " 【 %s 】 " label) (format " [ %s ] " label)))
             (map (make-sparse-keymap)))
        (if is-detail
            (define-key map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-set-type sym)))
          (define-key map [mouse-1] (lambda () (interactive) (my/stock-chart-set-type sym))))
        (setq res
              (concat res
                      (if active
                          (propertize label-str
                                      'face '(:weight bold :foreground "#ffffff" :background "#2e7d32")
                                      'mouse-face '(:background "#388e3c" :foreground "#ffffff")
                                      'local-map map
                                      'help-echo (format "現在選択中: %s" label))
                        (propertize label-str
                                    'face 'my/stock-chart-tab-type-inactive
                                    'mouse-face '(:background "#2e7d32" :foreground "#ffffff")
                                    'local-map map
                                    'help-echo (format "クリックして「%s」に切り替え" label)))
                      "  "))))
    (concat res " (切替: v キー)\n")))

(defun my/stock-chart--render-interval-tabs (current-interval &optional is-detail)
  "時間軸セレクターのクリック可能タブUI文字列を生成する。"
  (let ((tabs '((15min   "15分足" "1")
                (daily   "日足"   "d")
                (weekly  "週足"   "w")
                (monthly "月足"   "m")))
        (res " 時間軸: "))
    (dolist (tab tabs)
      (let* ((sym (nth 0 tab))
             (label (nth 1 tab))
             (key (nth 2 tab))
             (active (eq sym current-interval))
             (label-str (if active
                            (format " 【 %s (%s) 】 " label key)
                          (format " [ %s (%s) ] " label key)))
             (map (make-sparse-keymap)))
        (if is-detail
            (define-key map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-switch-interval sym)))
          (define-key map [mouse-1] (lambda () (interactive) (my/stock-chart-switch-interval sym))))
        (setq res
              (concat res
                      (if active
                          (propertize label-str
                                      'face '(:weight bold :foreground "#ffffff" :background "#005fb8")
                                      'mouse-face '(:background "#1a73e8" :foreground "#ffffff")
                                      'local-map map
                                      'help-echo (format "現在選択中: %s" label))
                        (propertize label-str
                                    'face 'my/stock-chart-tab-interval-inactive
                                    'mouse-face '(:background "#1a73e8" :foreground "#ffffff")
                                    'local-map map
                                    'help-echo (format "クリックして「%s」に切り替え" label)))
                      "  "))))
    (concat res " (切替: 1/d/w/m または [ / ])\n")))

;; ── レイアウト用ヘルパー ──

(defun my/stock-chart--chunk-list (list n)
  "LIST を N 個ずつのサブリストのリストに分割する。"
  (let ((result nil)
        (current nil)
        (count 0))
    (dolist (item list)
      (push item current)
      (setq count (1+ count))
      (when (= count n)
        (push (nreverse current) result)
        (setq current nil)
        (setq count 0)))
    (when current
      (push (nreverse current) result))
    (nreverse result)))

(defun my/stock-chart--calculate-columns ()
  "現在のウィンドウ幅に基づいて1行あたりの表示列数を計算する。"
  (let* ((win (or (get-buffer-window "*Stock-Charts*") (selected-window)))
         (frame (window-frame win))
         (win-px (if (and (display-graphic-p frame) (window-system frame))
                     (window-body-width win t)
                   (* (window-body-width win) (frame-char-width frame))))
         (col-width-px 344))
    (if (and win-px (> win-px 0))
        (max 1 (floor (/ win-px col-width-px)))
      (max 1 (floor (/ (window-body-width win) 42))))))

(defun my/stock-chart--col-text-width ()
  "画像幅 (320px) + 余白に相当するテキストの半角表示桁数を算出する。"
  (let* ((char-w (max 1 (frame-char-width))))
    (max 38 (/ 344 char-w))))

(defun my/stock-chart--pad-string (str target-width)
  "STR を TARGET-WIDTH の表示幅になるように末尾に空白を追加する。"
  (let ((w (string-width str)))
    (if (< w target-width)
        (concat str (make-string (- target-width w) ?\s))
      (concat str "  "))))

;; ── Imenu 連動 ──

(defun my/stock-chart-imenu-make-index ()
  "Imenu / Ilist 用の階層インデックスを返す。"
  my/stock-chart--imenu-index)

(defun my/stock-chart-imenu-jump ()
  "Imenu を起動して目的の銘柄やテーマへジャンプする。"
  (interactive)
  (call-interactively #'imenu))

;; ── 東証全上場銘柄リスト ＆ Consult 検索 ──

(defvar my/stock-chart--toushou-candidates-cache nil
  "東証全銘柄の Consult 候補リストのメモリキャッシュ。")

(defvar my/stock-chart--toushou-hash-cache nil
  "東証コードから銘柄名を取得するためのハッシュテーブルキャッシュ (コード -> 銘柄名)。")

(defun my/stock-chart--toushou-tsv-file ()
  "東証全銘柄 TSV の保存先パスを返す。"
  (expand-file-name "toushou_stocks.tsv" my/stock-chart-cache-dir))

(defun my/stock-chart--load-toushou-table ()
  "東証全銘柄のハッシュテーブル (コード -> 銘柄名) を返す。"
  (or my/stock-chart--toushou-hash-cache
      (let ((tsv-file (my/stock-chart--toushou-tsv-file)))
        (unless (file-exists-p tsv-file)
          (my/stock-chart-update-toushou-list t))
        (when (file-exists-p tsv-file)
          (let ((table (make-hash-table :test 'equal :size 4500)))
            (with-temp-buffer
              (insert-file-contents tsv-file)
              (goto-char (point-min))
              (while (not (eobp))
                (let ((line (string-trim (buffer-substring-no-properties
                                          (line-beginning-position)
                                          (line-end-position)))))
                  (unless (string-empty-p line)
                    (let* ((parts (split-string line "\t"))
                           (code (nth 0 parts))
                           (name (nth 1 parts)))
                      (when (and code name)
                        (puthash code name table)))))
                (forward-line 1)))
            (setq my/stock-chart--toushou-hash-cache table))))))

(defun my/stock-chart-lookup-name (code)
  "銘柄コード CODE に対応する銘柄名を東証マスタから取得する。見つからなければ nil。"
  (let ((table (my/stock-chart--load-toushou-table)))
    (and table (gethash code table))))

(defun my/stock-chart-update-toushou-list (&optional silent)
  "JPX 公式サイトから最新の東証上場銘柄一覧 (data_j.xlsx) を取得し、TSV を更新する。"
  (interactive)
  (unless (file-directory-p my/stock-chart-cache-dir)
    (make-directory my/stock-chart-cache-dir t))
  (let* ((xlsx-file (expand-file-name "data_j.xlsx" my/stock-chart-cache-dir))
         (py-script-in-pkg   (expand-file-name "update_toushou.py" my/stock-chart-pkg-dir))
         (py-script-in-cache (expand-file-name "update_toushou.py" my/stock-chart-cache-dir))
         (py-script-in-scripts (and (boundp 'user-emacs-directory)
                                    (expand-file-name "scripts/update_toushou.py" user-emacs-directory)))
         (py-script (cond ((file-exists-p py-script-in-pkg) py-script-in-pkg)
                          ((and py-script-in-scripts (file-exists-p py-script-in-scripts)) py-script-in-scripts)
                          ((file-exists-p py-script-in-cache) py-script-in-cache)
                          (t py-script-in-pkg)))
         (py-exe (or (executable-find "python3")
                     (executable-find "python")
                     "python"))
         (curl-exe (or (executable-find "curl")
                       (and (file-exists-p "C:/Windows/System32/curl.exe") "C:/Windows/System32/curl.exe")
                       "curl")))
    (unless silent (message "JPX 公式サイトから最新の東証全銘柄データを取得中..."))
    (call-process curl-exe nil nil nil "-s" "-L" "--ssl-no-revoke"
                  "-o" (replace-regexp-in-string "/" "\\\\" xlsx-file)
                  "https://www.jpx.co.jp/markets/statistics-equities/misc/tvdivq0000001vg2-att/data_j.xlsx")
    (when (file-exists-p py-script)
      (call-process py-exe nil nil nil
                    (replace-regexp-in-string "/" "\\\\" py-script)
                    (replace-regexp-in-string "/" "\\\\" my/stock-chart-cache-dir)))
    (setq my/stock-chart--toushou-candidates-cache nil)
    (setq my/stock-chart--toushou-hash-cache nil)
    (unless silent (message "東証全銘柄リスト (data_j.xlsx / TSV) の更新が完了しました!"))))

(defun my/stock-chart--load-toushou-stocks ()
  "東証全銘柄リストを読み込み、Consult 用の候補リストを返す。"
  (or my/stock-chart--toushou-candidates-cache
      (let ((tsv-file (my/stock-chart--toushou-tsv-file)))
        (unless (file-exists-p tsv-file)
          (my/stock-chart-update-toushou-list t))
        (when (file-exists-p tsv-file)
          (let ((cands nil))
            (with-temp-buffer
              (insert-file-contents tsv-file)
              (goto-char (point-min))
              (while (not (eobp))
                (let ((line (string-trim (buffer-substring-no-properties
                                          (line-beginning-position)
                                          (line-end-position)))))
                  (unless (string-empty-p line)
                    (let* ((parts (split-string line "\t"))
                           (code (nth 0 parts))
                           (name (nth 1 parts))
                           (market (nth 2 parts))
                           (industry (nth 3 parts))
                           (item-str (format "[%s] %s  〔%s / %s〕" code name market industry)))
                      (put-text-property 0 (length item-str) 'stock-code code item-str)
                      (put-text-property 0 (length item-str) 'stock-name name item-str)
                      (put-text-property 0 (length item-str) 'stock-market market item-str)
                      (put-text-property 0 (length item-str) 'stock-industry industry item-str)
                      (push item-str cands))))
                (forward-line 1)))
            (setq my/stock-chart--toushou-candidates-cache (nreverse cands)))))))

(defun my/stock-chart-search-all ()
  "東証全上場銘柄（約4,400銘柄）を Consult でインクリメンタル検索し、大画面チャートを開く。"
  (interactive)
  (let* ((cands (my/stock-chart--load-toushou-stocks)))
    (unless cands
      (error "東証銘柄データを読み込めませんでした。M-x my/stock-chart-update-toushou-list を実行してください。"))
    (let ((selected
           (if (fboundp 'consult--read)
               (consult--read cands
                              :prompt "東証全銘柄チャート検索: "
                              :category 'stock-chart
                              :sort nil
                              :require-match t
                              :group (lambda (cand transform)
                                       (if transform
                                           cand
                                         (get-text-property 0 'stock-industry cand))))
             (completing-read "東証全銘柄チャート検索: " cands nil t))))
      (when selected
        (let ((code (get-text-property 0 'stock-code selected))
              (name (get-text-property 0 'stock-name selected)))
          (if (and code name)
              (my/stock-chart-show-detail code name)
            (when (string-match "^\\[\\([^]]+\\)\\][ \t]*\\(.*?\\)[ \t]*〔" selected)
              (my/stock-chart-show-detail (match-string 1 selected)
                                          (match-string 2 selected)))))))))

(defun my/stock-chart-search-my ()
  "現在選択中の銘柄リストに登録されたマイ銘柄を Consult で検索し、大画面チャートを開く。"
  (interactive)
  (let* ((data (my/stock-chart--parse-list-file))
         (cands nil))
    (dolist (group data)
      (let ((theme (car group)))
        (dolist (stock (cdr group))
          (let* ((code (car stock))
                 (name (cdr stock))
                 (item-str (format "[%s] %s  (%s)" code name theme)))
            (put-text-property 0 (length item-str) 'stock-code code item-str)
            (put-text-property 0 (length item-str) 'stock-name name item-str)
            (put-text-property 0 (length item-str) 'stock-theme theme item-str)
            (push item-str cands)))))
    (setq cands (nreverse cands))
    (let ((selected
           (if (fboundp 'consult--read)
               (consult--read cands
                              :prompt "マイ銘柄チャート検索: "
                              :category 'stock-chart-my
                              :sort nil
                              :require-match t
                              :group (lambda (cand transform)
                                       (if transform cand (get-text-property 0 'stock-theme cand))))
             (completing-read "マイ銘柄チャート検索: " cands nil t))))
      (when selected
        (let ((code (get-text-property 0 'stock-code selected))
              (name (get-text-property 0 'stock-name selected)))
          (if (and code name)
              (my/stock-chart-show-detail code name)
            (when (string-match "^\\[\\([^]]+\\)\\][ \t]*\\(.*?\\)[ \t]*(" selected)
              (my/stock-chart-show-detail (match-string 1 selected)
                                          (match-string 2 selected)))))))))

;; ── 操作ヘルプ ──

(defun my/stock-chart-help ()
  "株式チャートブラウザの操作ヘルプを表示する。"
  (interactive)
  (let ((buf (get-buffer-create "*Stock-Chart-Help*"))
        (help-text (concat
                    "================================================================================\n"
                    " 株式チャートブラウザ 操作ヘルプ (F1 / h)\n"
                    "================================================================================\n\n"
                    "【銘柄リスト切り替え (マルチリスト 1〜9)】\n"
                    "  ( / )          : 前のリスト / 次の存在するリストへサイクル切り替え\n"
                    "  l (小文字L)    : 登録リスト一覧から選択して切り替え（新規作成も可能）\n"
                    "  M-1 〜 M-9     : リスト1〜9へダイレクト切り替え（未作成時は作成確認）\n"
                    "  ヘッダータブ   : 上部の [ リスト名 ] を直接マウスクリックして切替\n\n"
                    "【チャート形式の切り替え (v キー)】\n"
                    "  v              : 「楽天 (通常)」 ⇄ 「株ドラゴン (価格帯別出来高)」を切り替え\n"
                    "  ヘッダータブ   : マウスで [ 楽天 ] や [ 株ドラゴン ] を直接クリックして切替\n\n"
                    "【時間軸の切り替え】\n"
                    "  d / w / m      : 日足 / 週足 / 月足 切り替え (楽天・株ドラゴン両対応)\n"
                    "  1              : 15分足 切り替え (※楽天通常のみ)\n"
                    "  [ キー / ] キー: 時間軸を前後にサイクル切り替え\n\n"
                    "【検索・ジャンプ】\n"
                    "  s              : 東証全銘柄（約4,400銘柄）を Consult 検索して大画面表示\n"
                    "  S              : マイ銘柄（meigaralist.txt）を Consult 検索して大画面表示\n"
                    "  /              : 前方インクリメンタル検索 (isearch-forward)\n"
                    "  ?              : 後方インクリメンタル検索 (isearch-backward)\n"
                    "  i / M-g i      : Imenu で銘柄・テーマを検索してジャンプ (Ilist 連動)\n\n"
                    "【一覧サムネイル画面 (*Stock-Charts*)】\n"
                    "  クリック / RET : その銘柄の「大画面拡大モード」を開く\n"
                    "  b              : その銘柄の Yahoo!ファイナンス をブラウザで開く\n"
                    "  K              : その銘柄の 空売り.net をブラウザで開く\n"
                    "  e              : 銘柄リスト (meigaralist.txt) をポップアップで開いて編集\n"
                    "  g              : チャート画像を強制再取得して再配置\n"
                    "  j / n          : 次の銘柄へフォーカス移動 (横・縦)\n"
                    "  k / p          : 前の銘柄へフォーカス移動 (横・縦)\n"
                    "  <f1> / h       : この操作ヘルプを表示\n"
                    "  q              : バッファを閉じる (quit-window)\n\n"
                    "【大画面拡大モード (*Stock-Chart-Detail*)】\n"
                    "  画像クリック   : 一覧サムネイル画面に戻る\n"
                    "  [◀一覧に戻る]  : マウスクリックで一覧に戻る\n"
                    "  右クリック/戻る: マウス操作で一覧に戻る ([mouse-3] / [mouse-8])\n"
                    "  g              : チャート画像を強制再取得\n"
                    "  v              : 大画面のまま「楽天 (通常)」 ⇄ 「株ドラゴン (価格帯別出来高)」を切替\n"
                    "  n / p (j / k)  : 次の銘柄 / 前の銘柄の大画面チャートへ切り替え\n"
                    "  d / w / m      : 日足 / 週足 / 月足 切り替え (大画面のまま連動)\n"
                    "  [ キー / ] キー: 時間軸を前後にサイクル切り替え\n"
                    "  /  /  ?        : 前方検索 / 後方検索\n"
                    "  b              : Yahoo!ファイナンス をブラウザで開く (画面上ボタンあり)\n"
                    "  K              : 空売り.net をブラウザで開く (画面上ボタンあり)\n"
                    "  e              : 銘柄リスト (meigaralist.txt) をポップアップで開いて編集\n"
                    "  q / ESC        : 一覧サムネイル画面に戻る\n\n"
                    "【銘柄リスト編集 (e キー)】\n"
                    "  e を押すと銘柄リストが画面横（または下部）にポップアップ表示されます。\n"
                    "  チャートを見ながら銘柄コードやテーマの編集・追加・並べ替えが可能です。\n"
                    "  コードのみ（横が空欄）を入力しておくと、東証マスタから銘柄名を自動補完します。\n"
                    "  [C-c C-a]      : 東証マスタから銘柄名を一括補完（手動実行）\n"
                    "  [C-c C-c]      : 銘柄名を自動補完して保存・終了し、チャートを自動同期\n"
                    "  [C-c C-k]      : 変更を破棄して閉じる（C-sでの途中保存も可能）\n\n"
                    "※ [q] を押すとこのヘルプ画面を閉じます。\n"
                    "================================================================================\n")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert help-text)
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buf '(display-buffer-below-selected (window-height . 0.65)))))

;; ── メジャーモード定義 (*Stock-Charts*) ──

(defvar my/stock-chart-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q")          #'quit-window)
    (define-key map (kbd "g")          #'my/stock-chart-reload)
    (define-key map (kbd "e")          #'my/stock-chart-edit-list)
    (define-key map (kbd "l")          #'my/stock-chart-switch-list)
    (define-key map (kbd "(")          (lambda () (interactive) (my/stock-chart-cycle-list -1)))
    (define-key map (kbd ")")          (lambda () (interactive) (my/stock-chart-cycle-list 1)))
    (define-key map (kbd "M-1")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 1)))
    (define-key map (kbd "M-2")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 2)))
    (define-key map (kbd "M-3")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 3)))
    (define-key map (kbd "M-4")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 4)))
    (define-key map (kbd "M-5")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 5)))
    (define-key map (kbd "M-6")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 6)))
    (define-key map (kbd "M-7")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 7)))
    (define-key map (kbd "M-8")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 8)))
    (define-key map (kbd "M-9")        (lambda () (interactive) (my/stock-chart-switch-list-by-index 9)))
    (define-key map (kbd "v")          #'my/stock-chart-toggle-type)
    (define-key map (kbd "i")          #'my/stock-chart-imenu-jump)
    (define-key map (kbd "M-g i")      #'my/stock-chart-imenu-jump)
    (define-key map (kbd "s")          #'my/stock-chart-search-all)
    (define-key map (kbd "S")          #'my/stock-chart-search-my)
    (define-key map (kbd "/")          #'isearch-forward)
    (define-key map (kbd "?")          #'isearch-backward)
    (define-key map (kbd "d")          (lambda () (interactive) (my/stock-chart-switch-interval 'daily)))
    (define-key map (kbd "w")          (lambda () (interactive) (my/stock-chart-switch-interval 'weekly)))
    (define-key map (kbd "m")          (lambda () (interactive) (my/stock-chart-switch-interval 'monthly)))
    (define-key map (kbd "1")          (lambda () (interactive) (my/stock-chart-switch-interval '15min)))
    (define-key map (kbd "]")          (lambda () (interactive) (my/stock-chart-cycle-interval 1)))
    (define-key map (kbd "[")          (lambda () (interactive) (my/stock-chart-cycle-interval -1)))
    (define-key map (kbd "j")          #'my/stock-chart-next-stock)
    (define-key map (kbd "k")          #'my/stock-chart-prev-stock)
    (define-key map (kbd "n")          #'my/stock-chart-next-stock)
    (define-key map (kbd "p")          #'my/stock-chart-prev-stock)
    (define-key map (kbd "RET")        #'my/stock-chart-open-detail-at-point)
    (define-key map (kbd "<return>")    #'my/stock-chart-open-detail-at-point)
    (define-key map (kbd "b")          #'my/stock-chart-open-browser)
    (define-key map (kbd "K")          #'my/stock-chart-open-karauri)
    (define-key map (kbd "h")          #'my/stock-chart-help)
    (define-key map (kbd "<f1>")       #'my/stock-chart-help)
    (define-key map [mouse-1]          #'my/stock-chart-mouse-open-detail)
    (define-key map [mouse-2]          #'my/stock-chart-mouse-open-detail)
    map)
  "my/stock-chart-mode のキーマップ。")

(defun my/stock-chart--on-window-size-change (frame-or-win)
  "ウィンドウ幅が変更されたときに自動で再レイアウトする（ディバウンス処理）。"
  (when (and (eq (current-buffer) (get-buffer "*Stock-Charts*"))
             (get-buffer-window "*Stock-Charts*"))
    (let ((new-width (window-body-width (get-buffer-window "*Stock-Charts*") t)))
      (when (and new-width
                 my/stock-chart--last-window-width
                 (not (= new-width my/stock-chart--last-window-width)))
        (when (timerp my/stock-chart--resize-timer)
          (cancel-timer my/stock-chart--resize-timer))
        (setq my/stock-chart--resize-timer
              (run-with-idle-timer 0.3 nil
                                   (lambda ()
                                     (when (get-buffer-window "*Stock-Charts*")
                                       (my/stock-chart-render nil)))))))))

(define-derived-mode my/stock-chart-mode special-mode "StockChart"
  "株式チャートブラウザ専用モード。"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (setq-local imenu-create-index-function #'my/stock-chart-imenu-make-index)
  (add-hook 'window-size-change-functions #'my/stock-chart--on-window-size-change nil t))

;; ── サムネイル一覧バッファ描画 ──

(defun my/stock-chart-render (&optional force-fetch)
  "チャートバッファを生成・描画する。"
  (let* ((data (my/stock-chart--parse-list-file))
         (interval my/stock-chart-current-interval)
         (chart-type my/stock-chart-current-type)
         (all-stocks (cl-mapcan (lambda (theme-group) (copy-sequence (cdr theme-group))) data))
         (buf (get-buffer-create "*Stock-Charts*")))
    ;; 画像取得（第一候補 ＋ 取得失敗銘柄の自動バックアップ）
    (if (eq chart-type 'dragon)
        (progn
          (my/stock-chart--fetch-dragon-images all-stocks interval force-fetch)
          (let ((missing-stocks
                 (cl-remove-if (lambda (stk)
                                 (let ((code (car stk)))
                                   (my/stock-chart--valid-image-p (my/stock-chart--dragon-thumb-file code interval))))
                               all-stocks)))
            (when missing-stocks
              (my/stock-chart--fetch-images missing-stocks interval force-fetch))))
      (my/stock-chart--fetch-images all-stocks interval force-fetch)
      (let ((missing-stocks
             (cl-remove-if (lambda (stk)
                             (let* ((code (car stk))
                                    (sym (my/stock-chart--to-symbol code)))
                               (or (not (my/stock-chart--japan-stock-p code))
                                   (my/stock-chart--valid-image-p (my/stock-chart--cache-file sym interval)))))
                           all-stocks)))
        (when missing-stocks
          (my/stock-chart--fetch-dragon-images missing-stocks interval force-fetch))))

    (pop-to-buffer-same-window buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t)
            (cols (my/stock-chart--calculate-columns))
            (col-text-w (my/stock-chart--col-text-width))
            (orig-point (point))
            (imenu-index nil))
        (setq my/stock-chart--last-window-width (window-body-width (selected-window) t))
        (erase-buffer)
        (my/stock-chart-mode)
        ;; ヘッダー
        (insert (propertize "================================================================================\n" 'face 'font-lock-comment-face))
        (insert (propertize (format " 株式チャートブラウザ  (横 %d 列表示)\n" cols)
                            'face 'my/stock-chart-title))
        ;; リストタブUI ＆ 形式タブUI ＆ 時間軸タブUI
        (insert (my/stock-chart--render-list-tabs (my/stock-chart--current-file) nil))
        (insert (my/stock-chart--render-type-tabs chart-type nil))
        (insert (my/stock-chart--render-interval-tabs interval nil))
        (insert (propertize " [操作] l:リスト切替  (/):前後リスト  s:全銘柄検索  S:マイ検索  v:形式  d/w/m:足種  RET:拡大  b:Yahoo!  K:空売り  e:編集  h:ヘルプ\n"
                            'face 'font-lock-doc-face))
        (insert (propertize "================================================================================\n\n" 'face 'font-lock-comment-face))

        ;; 各テーマ・銘柄のグリッド描画
        (dolist (theme-group data)
          (let* ((theme-name (car theme-group))
                 (stocks (cdr theme-group))
                 (chunks (my/stock-chart--chunk-list stocks cols))
                 (theme-pos (copy-marker (point)))
                 (theme-imenu-items (list (cons (format "★ %s (先頭)" theme-name) theme-pos))))
            ;; テーマ見出し
            (insert (propertize (format "■ [%s]  (%d 銘柄)\n" theme-name (length stocks))
                                'face 'my/stock-chart-theme-header
                                'theme-name theme-name))
            (insert (propertize (make-string (min 120 (* cols col-text-w)) ?-)
                                'face 'font-lock-comment-face)
                    "\n")
            ;; チャンク（行）ごとに横並び描画 (ピクセル単位の位置揃え、代替表示)
            (dolist (chunk chunks)
              (let* ((col-idx 0)
                     ;; 各銘柄の解決済みデータ: (stock sym file-path actual-type is-fallback)
                     (resolved-items
                      (mapcar (lambda (stock)
                                (let* ((code (car stock))
                                       (sym (my/stock-chart--to-symbol code))
                                       (res (my/stock-chart--resolve-thumb-image code sym interval chart-type)))
                                  (list stock sym (nth 0 res) (nth 1 res) (nth 2 res))))
                              chunk)))
                ;; 1行目: 各列のヘッダーテキスト (コード・銘柄名 ＋ 足種/形式/代替バッジ)
                (dolist (item resolved-items)
                  (let* ((stock (nth 0 item))
                         (sym (nth 1 item))
                         (actual-type (nth 3 item))
                         (is-fallback (nth 4 item))
                         (code (car stock))
                         (name (cdr stock))
                         (stock-pos (copy-marker (point)))
                         (badge (let ((short-int (my/stock-chart--interval-short-name interval)))
                                  (cond
                                   ((and is-fallback (eq actual-type 'rakuten))
                                    (format "%s (楽天代替)" short-int))
                                   ((and is-fallback (eq actual-type 'dragon))
                                    (format "価格帯別・%s (ドラゴン代替)" short-int))
                                   ((eq actual-type 'dragon)
                                    (format "価格帯別・%s" short-int))
                                   (t short-int))))
                         (label (format "▶ [%s] %s  〔%s〕" code name badge))
                         (next-col-px (* (1+ col-idx) 344)))
                    (push (cons (format "[%s] %s" code name) stock-pos) theme-imenu-items)
                    (insert (propertize label
                                        'face 'my/stock-chart-stock-label
                                        'stock-code code
                                        'stock-name name
                                        'stock-sym sym
                                        'mouse-face 'highlight
                                        'help-echo (format "%s (%s) - クリック/RETで大画面拡大, bでYahoo!, Kで空売り.net" name code)))
                    ;; 次のカラムの開始ピクセル位置へ正確に位置合わせ
                    (when (< col-idx (1- (length resolved-items)))
                      (insert (propertize " " 'display `(space :align-to (,next-col-px)))))
                    (setq col-idx (1+ col-idx))))
                (insert "\n")

                ;; 2行目: 各列のチャート画像（取得・表示失敗時は画像を非表示）
                (setq col-idx 0)
                (dolist (item resolved-items)
                  (let* ((stock (nth 0 item))
                         (sym (nth 1 item))
                         (cache-path (nth 2 item))
                         (code (car stock))
                         (name (cdr stock))
                         (next-col-px (* (1+ col-idx) 344)))
                    (if (and cache-path (my/stock-chart--valid-image-p cache-path))
                        (condition-case nil
                            (let ((img (create-image cache-path nil nil :ascent 'center)))
                              (insert (propertize " "
                                                  'display img
                                                  'stock-code code
                                                  'stock-name name
                                                  'stock-sym sym
                                                  'mouse-face 'highlight
                                                  'help-echo (format "%s (%s) - クリックまたはRETで大画面拡大表示" name code))))
                          (error
                           ;; エラー時は画像を非表示にして控えめなテキストのみ
                           (insert (propertize " [チャート非表示]"
                                               'face 'font-lock-comment-face
                                               'stock-code code
                                               'stock-name name
                                               'stock-sym sym))))
                      ;; 取得失敗時は画像要素を一切挿入せず非表示
                      (insert (propertize " [チャートなし]"
                                          'face 'font-lock-comment-face
                                          'stock-code code
                                          'stock-name name
                                          'stock-sym sym)))
                    ;; 次のカラムの開始ピクセル位置へ正確に位置合わせ
                    (when (< col-idx (1- (length resolved-items)))
                      (insert (propertize " " 'display `(space :align-to (,next-col-px)))))
                    (setq col-idx (1+ col-idx))))
                (insert "\n\n")))
            (push (cons theme-name (nreverse theme-imenu-items)) imenu-index)
            (insert "\n")))
        (setq-local my/stock-chart--imenu-index (nreverse imenu-index))
        (if (> orig-point 1)
            (goto-char (min orig-point (point-max)))
          (goto-char (point-min))
          (search-forward "▶" nil t)
          (backward-char 1))))))

;; ── 大画面チャート拡大モード (*Stock-Chart-Detail*) ──

(defvar-local my/stock-chart-detail--code nil "大画面モードの現在の銘柄コード。")
(defvar-local my/stock-chart-detail--name nil "大画面モードの現在の銘柄名。")
(defvar-local my/stock-chart-detail--interval 'daily "大画面モードの現在の足種。")
(defvar-local my/stock-chart-detail--type 'rakuten "大画面モードの現在のチャート形式。")

(defvar my/stock-chart-detail-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q")          #'my/stock-chart-detail-quit)
    (define-key map (kbd "<escape>")   #'my/stock-chart-detail-quit)
    (define-key map (kbd "g")          #'my/stock-chart-detail-reload)
    (define-key map (kbd "s")          #'my/stock-chart-search-all)
    (define-key map (kbd "S")          #'my/stock-chart-search-my)
    (define-key map (kbd "l")          #'my/stock-chart-switch-list)
    (define-key map (kbd "(")          (lambda () (interactive) (my/stock-chart-cycle-list -1)))
    (define-key map (kbd ")")          (lambda () (interactive) (my/stock-chart-cycle-list 1)))
    (define-key map (kbd "e")          #'my/stock-chart-edit-list)
    (define-key map (kbd "v")          #'my/stock-chart-detail-toggle-type)
    (define-key map (kbd "n")          #'my/stock-chart-detail-next-stock)
    (define-key map (kbd "p")          #'my/stock-chart-detail-prev-stock)
    (define-key map (kbd "j")          #'my/stock-chart-detail-next-stock)
    (define-key map (kbd "k")          #'my/stock-chart-detail-prev-stock)
    (define-key map (kbd "1")          (lambda () (interactive) (my/stock-chart-detail-switch-interval '15min)))
    (define-key map (kbd "d")          (lambda () (interactive) (my/stock-chart-detail-switch-interval 'daily)))
    (define-key map (kbd "w")          (lambda () (interactive) (my/stock-chart-detail-switch-interval 'weekly)))
    (define-key map (kbd "m")          (lambda () (interactive) (my/stock-chart-detail-switch-interval 'monthly)))
    (define-key map (kbd "]")          (lambda () (interactive) (my/stock-chart-detail-cycle-interval 1)))
    (define-key map (kbd "[")          (lambda () (interactive) (my/stock-chart-detail-cycle-interval -1)))
    (define-key map (kbd "b")          #'my/stock-chart-detail-open-browser)
    (define-key map (kbd "K")          #'my/stock-chart-detail-open-karauri)
    (define-key map (kbd "RET")        #'my/stock-chart-detail-open-browser)
    (define-key map (kbd "<return>")    #'my/stock-chart-detail-open-browser)
    (define-key map (kbd "/")          #'isearch-forward)
    (define-key map (kbd "?")          #'isearch-backward)
    (define-key map (kbd "h")          #'my/stock-chart-help)
    (define-key map (kbd "<f1>")       #'my/stock-chart-help)
    (define-key map [mouse-3]          #'my/stock-chart-detail-quit)
    (define-key map [mouse-8]          #'my/stock-chart-detail-quit)
    map)
  "大画面詳細モードのキーマップ。")

(define-derived-mode my/stock-chart-detail-mode special-mode "StockDetail"
  "大画面株式チャート詳細モード。"
  (setq buffer-read-only t)
  (setq truncate-lines t))

(defun my/stock-chart-show-detail (code name &optional interval type force)
  "指定銘柄の大画面チャートを画面いっぱいに表示する。"
  (let* ((int (or interval my/stock-chart-current-interval))
         (typ (or type my/stock-chart-current-type))
         (sym (my/stock-chart--to-symbol code))
         (resolved (my/stock-chart--resolve-large-image code sym int typ force))
         (large-file (nth 0 resolved))
         (actual-type (nth 1 resolved))
         (is-fallback (nth 2 resolved))
         (buf (get-buffer-create "*Stock-Chart-Detail*")))
    (pop-to-buffer-same-window buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (my/stock-chart-detail-mode)
        (setq-local my/stock-chart-detail--code code)
        (setq-local my/stock-chart-detail--name name)
        (setq-local my/stock-chart-detail--interval int)
        (setq-local my/stock-chart-detail--type typ)
        ;; ヘッダー
        (insert (propertize "================================================================================\n" 'face 'font-lock-comment-face))
        (let ((badge (cond
                      ((and is-fallback (eq actual-type 'rakuten))
                       (format "%s (※株ドラゴン未提供のため楽天通常で代替表示)" (my/stock-chart--interval-short-name int)))
                      ((and is-fallback (eq actual-type 'dragon))
                       (format "価格帯別出来高・%s (※楽天証券未提供のため株ドラゴンで代替表示)" (my/stock-chart--interval-short-name int)))
                      ((eq actual-type 'dragon)
                       (format "価格帯別出来高・%s (株ドラゴン)" (my/stock-chart--interval-short-name int)))
                      (t
                       (my/stock-chart--interval-short-name int)))))
          (insert (propertize (format " [%s] %s  〔%s〕 " code name badge)
                              'face 'my/stock-chart-detail-title))
          ;; Yahoo! 外部リンクボタン
          (let ((y-map (make-sparse-keymap)))
            (define-key y-map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-open-browser)))
            (insert (propertize " [ Yahoo! (b) ] "
                                'face 'my/stock-chart-link-button
                                'mouse-face 'highlight
                                'local-map y-map
                                'help-echo "クリックで Yahoo!ファイナンス を開く (b)"))
            (insert " "))
          ;; 空売り.net 外部リンクボタン（日本株のみ）
          (when (my/stock-chart--japan-stock-p code)
            (let ((k-map (make-sparse-keymap)))
              (define-key k-map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-open-karauri)))
              (insert (propertize " [ 空売り.net (K) ] "
                                  'face 'my/stock-chart-link-button
                                  'mouse-face 'highlight
                                  'local-map k-map
                                  'help-echo "クリックで 空売り.net を開く (K)"))))
          (insert "\n"))
        ;; 形式タブUI ＆ 時間軸タブUI
        (insert (my/stock-chart--render-type-tabs typ t))
        (insert (my/stock-chart--render-interval-tabs int t))
        ;; 一覧に戻るボタン ＆ 操作案内
        (let ((back-map (make-sparse-keymap)))
          (define-key back-map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-quit)))
          (insert (propertize " [ ◀ 一覧に戻る (q) ] "
                              'face 'my/stock-chart-back-button
                              'mouse-face '(:background "#f44336" :foreground "#ffffff")
                              'local-map back-map
                              'help-echo "クリックで一覧画面に戻る (q / 右クリック / 画像クリック)"))
          (insert (propertize "  g:更新  s:全検索  S:マイ検索  v:形式  d/w/m:足種  n/p:銘柄送り  b:Yahoo!  K:空売り  h:ヘルプ\n"
                              'face 'font-lock-doc-face)))
        (insert (propertize "================================================================================\n\n" 'face 'font-lock-comment-face))
        ;; 大画面チャート画像の挿入（クリックで一覧へ戻る）
        (if (and large-file (my/stock-chart--valid-image-p large-file))
            (condition-case nil
                (let* ((img (create-image large-file nil nil :ascent 'center))
                       (img-map (make-sparse-keymap)))
                  (define-key img-map [mouse-1] (lambda () (interactive) (my/stock-chart-detail-quit)))
                  (define-key img-map [mouse-2] (lambda () (interactive) (my/stock-chart-detail-quit)))
                  (insert "  ")
                  (insert (propertize " "
                                      'display img
                                      'local-map img-map
                                      'mouse-face 'highlight
                                      'help-echo "クリックで一覧画面に戻る (q)"))
                  (insert "\n\n"))
              (error
               (insert (propertize "   [チャート画像を表示できませんでした]\n\n"
                                   'face 'font-lock-comment-face))))
          (insert (propertize "   [チャート画像を取得できませんでした (b キーで Yahoo!ファイナンス を開けます)]\n\n"
                              'face 'font-lock-comment-face)))
        (goto-char (point-min))))))

(defun my/stock-chart-detail-reload ()
  "大画面モードで現在の銘柄チャートを強制再取得して再描画する。"
  (interactive)
  (when my/stock-chart-detail--code
    (my/stock-chart-show-detail my/stock-chart-detail--code
                                my/stock-chart-detail--name
                                my/stock-chart-detail--interval
                                my/stock-chart-detail--type
                                t)
    (message "大画面チャートを最新情報に更新しました。")))

(defun my/stock-chart-detail-set-type (new-type)
  "大画面モードのチャート形式を切り替える。"
  (interactive)
  (setq my/stock-chart-current-type new-type)
  (when my/stock-chart-detail--code
    (my/stock-chart-show-detail my/stock-chart-detail--code
                                my/stock-chart-detail--name
                                my/stock-chart-detail--interval
                                new-type)))

(defun my/stock-chart-detail-toggle-type ()
  "大画面モードでチャート形式をトグル切り替えする。"
  (interactive)
  (let ((next-type (if (eq my/stock-chart-detail--type 'dragon) 'rakuten 'dragon)))
    (my/stock-chart-detail-set-type next-type)))

(defun my/stock-chart-detail-switch-interval (new-interval)
  "大画面モードの時間軸を NEW-INTERVAL に切り替える。"
  (interactive)
  (setq my/stock-chart-current-interval new-interval)
  (when my/stock-chart-detail--code
    (my/stock-chart-show-detail my/stock-chart-detail--code
                                my/stock-chart-detail--name
                                new-interval
                                my/stock-chart-detail--type)))

(defun my/stock-chart-detail-cycle-interval (direction)
  "大画面モードの時間軸を前後にサイクル切り替えする。"
  (let* ((list my/stock-chart-intervals)
         (idx (cl-position my/stock-chart-detail--interval list))
         (new-idx (mod (+ idx direction) (length list)))
         (next-int (nth new-idx list)))
    (my/stock-chart-detail-switch-interval next-int)))

(defun my/stock-chart-detail-next-stock ()
  "大画面モードで次の銘柄へ進む。"
  (interactive)
  (let* ((all (my/stock-chart--all-stocks))
         (codes (mapcar #'car all))
         (idx (cl-position my/stock-chart-detail--code codes :test #'equal))
         (next-idx (if idx (mod (1+ idx) (length all)) 0))
         (next-stock (nth next-idx all)))
    (when next-stock
      (my/stock-chart-show-detail (car next-stock) (cdr next-stock)
                                  my/stock-chart-detail--interval
                                  my/stock-chart-detail--type))))

(defun my/stock-chart-detail-prev-stock ()
  "大画面モードで前の銘柄へ戻る。"
  (interactive)
  (let* ((all (my/stock-chart--all-stocks))
         (codes (mapcar #'car all))
         (idx (cl-position my/stock-chart-detail--code codes :test #'equal))
         (prev-idx (if idx (mod (1- idx) (length all)) (1- (length all))))
         (prev-stock (nth prev-idx all)))
    (when prev-stock
      (my/stock-chart-show-detail (car prev-stock) (cdr prev-stock)
                                  my/stock-chart-detail--interval
                                  my/stock-chart-detail--type))))

(defun my/stock-chart-detail-open-browser ()
  "大画面モードの銘柄を Yahoo!ファイナンス で開く。"
  (interactive)
  (when my/stock-chart-detail--code
    (let* ((code my/stock-chart-detail--code)
           (url (if (string-match-p "^[0-9]+[A-Za-z]?$" code)
                    (format "https://finance.yahoo.co.jp/quote/%s.T" code)
                  (format "https://finance.yahoo.co.jp/quote/%s" code))))
      (browse-url url)
      (message "ブラウザで開きました: %s (%s)" code url))))

(defun my/stock-chart--karauri-url (code)
  "指定銘柄の空売り.net URL を生成する。日本株でない場合は nil。"
  (let ((clean (replace-regexp-in-string "（.*）" "" code)))
    (when (my/stock-chart--japan-stock-p clean)
      (format "https://karauri.net/%s/" clean))))

(defun my/stock-chart-detail-open-karauri ()
  "大画面モードの銘柄を既定ブラウザで空売り.net を開く。"
  (interactive)
  (when my/stock-chart-detail--code
    (let ((url (my/stock-chart--karauri-url my/stock-chart-detail--code)))
      (if url
          (progn
            (browse-url url)
            (message "空売り.net を開きました: %s (%s)" my/stock-chart-detail--code url))
        (message "空売り.net は日本株のみ対応しています (%s)" my/stock-chart-detail--code)))))

(defun my/stock-chart-detail-quit ()
  "大画面モードを閉じ、一覧サムネイル画面に戻る。"
  (interactive)
  (quit-window t)
  (when (get-buffer "*Stock-Charts*")
    (pop-to-buffer-same-window "*Stock-Charts*")))

(defun my/stock-chart-open-detail-at-point ()
  "カーソル位置の銘柄を大画面拡大モードで開く。"
  (interactive)
  (let ((code (or (get-text-property (point) 'stock-code)
                  (save-excursion
                    (when (search-backward "▶" nil t)
                      (get-text-property (point) 'stock-code)))))
        (name (or (get-text-property (point) 'stock-name)
                  (save-excursion
                    (when (search-backward "▶" nil t)
                      (get-text-property (point) 'stock-name))))))
    (if code
        (my/stock-chart-show-detail code (or name code))
      (message "銘柄の位置で押してください。"))))

(defun my/stock-chart-mouse-open-detail (event)
  "マウスクリックした位置の銘柄を大画面拡大モードで開く。"
  (interactive "e")
  (let ((pos (posn-point (event-end event))))
    (when pos
      (let ((code (get-text-property pos 'stock-code))
            (name (get-text-property pos 'stock-name)))
        (if code
            (my/stock-chart-show-detail code (or name code))
          (message "銘柄をクリックしてください。"))))))

;; ── インタラクティブコマンド ──

(defun my/stock-chart-set-type (type)
  "チャート形式を TYPE ('rakuten または 'dragon) に切り替える。"
  (interactive)
  (setq my/stock-chart-current-type type)
  (my/stock-chart-render nil)
  (message "チャート形式を「%s」に切り替えました。"
           (if (eq type 'dragon) "株ドラゴン (価格帯別出来高)" "楽天証券 (通常)")))

(defun my/stock-chart-toggle-type ()
  "チャート形式を通常 (楽天証券) と 価格帯別出来高 (株ドラゴン) でトグル切り替えする。"
  (interactive)
  (my/stock-chart-set-type (if (eq my/stock-chart-current-type 'dragon) 'rakuten 'dragon)))

(defun my/stock-chart-switch-interval (interval)
  "足種を INTERVAL に切り替えて再描画する。"
  (interactive)
  (setq my/stock-chart-current-interval interval)
  (my/stock-chart-render nil)
  (message "足種を「%s」に切り替えました。" (my/stock-chart--interval-name interval)))

(defun my/stock-chart-cycle-interval (direction)
  "時間軸を前後にサイクル切り替えする (DIRECTION: 1 で次, -1 で前)。"
  (let* ((list my/stock-chart-intervals)
         (idx (cl-position my/stock-chart-current-interval list))
         (new-idx (mod (+ idx direction) (length list)))
         (next-int (nth new-idx list)))
    (my/stock-chart-switch-interval next-int)))

;; ── リスト編集 ＆ 自動同期 ──

(defvar-local my/stock-chart-edit--saved-winconf nil
  "リスト編集開始前のウィンドウ構成。")

(defvar-local my/stock-chart-edit--origin-buffer nil
  "編集を呼び出した元のバッファ (*Stock-Charts* または *Stock-Chart-Detail*)。")

(defun my/stock-chart--on-list-saved ()
  "meigaralist.txt 保存時にチャートバッファを自動同期する。"
  (when (get-buffer "*Stock-Charts*")
    (message "銘柄リストの保存を検知: チャートを再描画中...")
    (my/stock-chart-render nil)
    (message "チャートを最新の銘柄リストと同期しました。")))

(defcustom my/stock-chart-auto-complete-names-on-save t
  "銘柄リスト保存時に、コード単体（銘柄名が空）の行を東証マスタから自動補完するかどうか。"
  :type 'boolean
  :group 'my/stock-chart)

(defun my/stock-chart-edit-complete-names (&optional silent)
  "編集バッファ内の銘柄行で、コードのみ（銘柄名が空）の行に東証マスタから銘柄名を自動補完・追記する。"
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (not (eobp))
        (let ((line (string-trim (buffer-substring-no-properties
                                  (line-beginning-position)
                                  (line-end-position)))))
          (unless (or (string-empty-p line)
                      (string-prefix-p "#" line)
                      (string-prefix-p "//" line)
                      (string-prefix-p "[" line))
            (when (string-match "^\\([0-9A-Za-z]+\\)[ \t]*$" line)
              (let* ((code (match-string 1 line))
                     (name (my/stock-chart-lookup-name code)))
                (when name
                  (delete-region (line-beginning-position) (line-end-position))
                  (insert (format "%s %s" code name))
                  (cl-incf count))))))
        (forward-line 1))
      (if (> count 0)
          (message "%d 件の銘柄名を東証マスタから補完しました。" count)
        (unless silent
          (message "補完対象の銘柄コードはありませんでした。"))))))

(defun my/stock-chart-edit-finish ()
  "銘柄リストの変更を保存し、バッファを閉じて元のチャート画面へ復帰・再描画する。"
  (interactive)
  (let ((winconf my/stock-chart-edit--saved-winconf)
        (origin-buf my/stock-chart-edit--origin-buffer)
        (edit-buf (current-buffer)))
    (when my/stock-chart-auto-complete-names-on-save
      (my/stock-chart-edit-complete-names t))
    (when (buffer-modified-p)
      (save-buffer))
    (setq my/stock-chart-edit--saved-winconf nil)
    (kill-buffer edit-buf)
    (when (and winconf (window-configuration-p winconf))
      (set-window-configuration winconf))
    (if (and origin-buf (buffer-live-p origin-buf))
        (pop-to-buffer-same-window origin-buf)
      (when (get-buffer "*Stock-Charts*")
        (pop-to-buffer-same-window "*Stock-Charts*")))
    (when (get-buffer "*Stock-Charts*")
      (my/stock-chart-render nil))
    (message "銘柄リストを保存し、チャートを最新状態に更新しました。")))

(defun my/stock-chart-edit-abort ()
  "銘柄リストの編集を破棄してバッファを閉じ、元のチャート画面へ復帰する。"
  (interactive)
  (let ((winconf my/stock-chart-edit--saved-winconf)
        (origin-buf my/stock-chart-edit--origin-buffer)
        (edit-buf (current-buffer)))
    (if (buffer-modified-p)
        (when (yes-or-no-p "変更を破棄して銘柄リスト編集を終了しますか？ ")
          (set-buffer-modified-p nil)
          (setq my/stock-chart-edit--saved-winconf nil)
          (kill-buffer edit-buf)
          (when (and winconf (window-configuration-p winconf))
            (set-window-configuration winconf))
          (if (and origin-buf (buffer-live-p origin-buf))
              (pop-to-buffer-same-window origin-buf)
            (when (get-buffer "*Stock-Charts*")
              (pop-to-buffer-same-window "*Stock-Charts*")))
          (message "銘柄リストの編集を破棄しました。"))
      (setq my/stock-chart-edit--saved-winconf nil)
      (kill-buffer edit-buf)
      (when (and winconf (window-configuration-p winconf))
        (set-window-configuration winconf))
      (if (and origin-buf (buffer-live-p origin-buf))
          (pop-to-buffer-same-window origin-buf)
        (when (get-buffer "*Stock-Charts*")
          (pop-to-buffer-same-window "*Stock-Charts*")))
      (message "銘柄リスト編集を終了しました。"))))

(defvar my/stock-chart-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'my/stock-chart-edit-finish)
    (define-key map (kbd "C-c C-a") #'my/stock-chart-edit-complete-names)
    (define-key map (kbd "C-c C-k") #'my/stock-chart-edit-abort)
    (define-key map (kbd "C-c q")   #'my/stock-chart-edit-finish)
    map)
  "銘柄リスト編集バッファ用のキーマップ。")

(define-minor-mode my/stock-chart-edit-mode
  "銘柄リスト編集用の一時マイナーモード。"
  :lighter " [StockEdit]"
  :keymap my/stock-chart-edit-mode-map)

(defun my/stock-chart--display-edit-buffer (buf)
  "BUF を適切なウィンドウ位置にポップアップ表示する。"
  (cond
   ((eq my/stock-chart-edit-window-position 'same-window)
    (pop-to-buffer-same-window buf))
   ((eq my/stock-chart-edit-window-position 'below)
    (select-window (display-buffer-below-selected buf '((window-height . 0.45)))))
   ((eq my/stock-chart-edit-window-position 'right)
    (if (>= (window-body-width) 110)
        (select-window (display-buffer-in-direction buf '((direction . right) (window-width . 0.4))))
      (select-window (display-buffer-below-selected buf '((window-height . 0.45))))))
   (t
    (pop-to-buffer buf))))

(defun my/stock-chart-edit-list ()
  "現在選択中のリストファイルをポップアップで開いて編集する（保存時に自動同期・終了）。"
  (interactive)
  (let* ((curr-file (my/stock-chart--current-file))
         (origin-buf (current-buffer))
         (saved-winconf (current-window-configuration))
         (buf (find-file-noselect curr-file)))
    (my/stock-chart--display-edit-buffer buf)
    (with-current-buffer buf
      (setq-local my/stock-chart-edit--saved-winconf saved-winconf)
      (setq-local my/stock-chart-edit--origin-buffer origin-buf)
      (my/stock-chart-edit-mode 1)
      (add-hook 'before-save-hook
                (lambda ()
                  (when my/stock-chart-auto-complete-names-on-save
                    (my/stock-chart-edit-complete-names t)))
                nil t)
      (add-hook 'after-save-hook #'my/stock-chart--on-list-saved nil t)
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (when (window-configuration-p my/stock-chart-edit--saved-winconf)
                    (set-window-configuration my/stock-chart-edit--saved-winconf))
                  (when (and my/stock-chart-edit--origin-buffer
                              (buffer-live-p my/stock-chart-edit--origin-buffer))
                    (pop-to-buffer-same-window my/stock-chart-edit--origin-buffer)))
                nil t)
      (setq-local header-line-format
                  (list
                   (propertize " [ 保存して閉じる (C-c C-c) ] "
                               'face 'my/stock-chart-btn-save
                               'mouse-face 'highlight
                               'help-echo "クリックで保存して閉じます (C-c C-c)"
                               'local-map (let ((map (make-sparse-keymap)))
                                            (define-key map [header-line mouse-1]
                                              (lambda () (interactive) (my/stock-chart-edit-finish)))
                                            (define-key map [header-line mouse-2]
                                              (lambda () (interactive) (my/stock-chart-edit-finish)))
                                            map))
                   " "
                   (propertize " [ 銘柄名補完 (C-c C-a) ] "
                               'face 'my/stock-chart-link-button
                               'mouse-face 'highlight
                               'help-echo "クリックでコードのみの行に銘柄名を一括補完します (C-c C-a)"
                               'local-map (let ((map (make-sparse-keymap)))
                                            (define-key map [header-line mouse-1]
                                              (lambda () (interactive) (my/stock-chart-edit-complete-names)))
                                            (define-key map [header-line mouse-2]
                                              (lambda () (interactive) (my/stock-chart-edit-complete-names)))
                                            map))
                   " "
                   (propertize " [ キャンセル (C-c C-k) ] "
                               'face 'my/stock-chart-btn-cancel
                               'mouse-face 'highlight
                               'help-echo "クリックで破棄して閉じます (C-c C-k)"
                               'local-map (let ((map (make-sparse-keymap)))
                                            (define-key map [header-line mouse-1]
                                              (lambda () (interactive) (my/stock-chart-edit-abort)))
                                            (define-key map [header-line mouse-2]
                                              (lambda () (interactive) (my/stock-chart-edit-abort)))
                                            map))
                   (propertize (format "   %s (C-sで途中保存)" (file-name-nondirectory curr-file))
                               'face 'font-lock-comment-face))))
    (message "%s を開きました。[C-c C-c] で保存して閉じる / [C-c C-a] で銘柄名補完 / [C-c C-k] でキャンセル"
             (file-name-nondirectory curr-file))))

;;;###autoload
(defun my/stock-chart-open ()
  "株式チャートブラウザを開く。"
  (interactive)
  (my/stock-chart-render nil))

(defun my/stock-chart-reload ()
  "meigaralist.txt を再読み込みし、最新画像を強制再取得して更新する。"
  (interactive)
  (my/stock-chart-render t)
  (message "チャートを最新情報に更新しました。"))

(defun my/stock-chart-open-browser ()
  "カーソル位置の銘柄を既定ブラウザ（Yahoo!ファイナンス）で開く。"
  (interactive)
  (let ((code (or (get-text-property (point) 'stock-code)
                  (save-excursion
                    (when (search-backward "▶" nil t)
                      (get-text-property (point) 'stock-code))))))
    (if code
        (let ((url (if (string-match-p "^[0-9]+[A-Za-z]?$" code)
                       (format "https://finance.yahoo.co.jp/quote/%s.T" code)
                     (format "https://finance.yahoo.co.jp/quote/%s" code))))
          (browse-url url)
          (message "ブラウザで開きました: %s (%s)" code url))
      (message "銘柄の位置で b を押してください。"))))

(defun my/stock-chart-open-karauri ()
  "カーソル位置の銘柄を既定ブラウザで空売り.net を開く。"
  (interactive)
  (let ((code (or (get-text-property (point) 'stock-code)
                  (save-excursion
                    (when (search-backward "▶" nil t)
                      (get-text-property (point) 'stock-code))))))
    (if code
        (let ((url (my/stock-chart--karauri-url code)))
          (if url
              (progn
                (browse-url url)
                (message "空売り.net を開きました: %s (%s)" code url))
            (message "空売り.net は日本株のみ対応しています (%s)" code)))
      (message "銘柄の位置で K を押してください。"))))

(defun my/stock-chart-next-stock ()e
  "次の銘柄へジャンプする（横並び対応）。"
  (interactive)
  (forward-char 1)
  (if (search-forward "▶" nil t)
      (backward-char 1)
    (goto-char (point-max))))

(defun my/stock-chart-prev-stock ()
  "前の銘柄へジャンプする（横並び対応）。"
  (interactive)
  (if (search-backward "▶" nil t)
      nil
    (goto-char (point-min))))

;;;###autoload
(defalias 'stock-charts #'my/stock-chart-open)
;;;###autoload
(defalias 'stock-charts-search-all #'my/stock-chart-search-all)
;;;###autoload
(defalias 'consult-stock-chart-all #'my/stock-chart-search-all)


(provide 'stock-charts)
(provide 'my-stock-chart)
;;; stock-charts.el ends here
