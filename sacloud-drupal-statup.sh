#!/bin/bash

# @sacloud-once
#
# @sacloud-require-archive distro-centos distro-ver-7.*
#
# @sacloud-desc-begin
#   Cent OS 7 に Drupal 7 と必要なミドルウェアをインストールします。
# @sacloud-desc-end
#
# Drupal の管理ユーザーの入力フォームの設定
# @sacloud-text required shellarg maxlen=128 site_name "Drupal サイト名"
# @sacloud-text required shellarg maxlen=60 ex=Admin user_name "Drupal 管理ユーザーの名前"
# @sacloud-password required shellarg maxlen=60 password "Drupal 管理ユーザーのパスワード"
# @sacloud-text required shellarg maxlen=254 ex=your.name@example.com mail "Drupal 管理ユーザーのメールアドレス"

# 必要なミドルウェアを全てインストール
yum makecache fast
yum -y install php php-mysql php-gd php-dom php-mbstring mariadb mariadb-server httpd
yum -y install --enablerepo=remi php-pecl-apcu php-pecl-zendopcache

# Drupal で .htaccess を使用するため /var/www/html ディレクトリに対してオーバーライドを全て許可する
patch /etc/httpd/conf/httpd.conf << EOS
151c151
<     AllowOverride None
---
>     AllowOverride All
EOS

# MySQL の max_allowed_packet の設定を 16MB まで引き上げる
patch /etc/my.cnf << EOS
9a10
> max_allowed_packet=16M
EOS

# PHP のデフォルトのタイムゾーンを東京に設定
# Drupal のデフォルトのタイムゾーンにもなる
patch /etc/php.ini << EOS
672c672
< post_max_size = 8M
---
> post_max_size = 16M
800c800
< upload_max_filesize = 2M
---
> upload_max_filesize = 16M
878c878
< ;date.timezone =
---
> date.timezone = Asia/Tokyo
EOS

# ファイルアップロード時のプログレスバーを表示できるようにする
patch /etc/php.d/apcu.ini << EOS
67c67
< ;apc.rfc1867=0
---
> apc.rfc1867=1
EOS

# MySQL サーバーを自動起動するようにして起動
systemctl enable mariadb.service
systemctl start mariadb.service

# 最新版の Drush をダウンロードする
php -r "readfile('http://files.drush.org/drush.phar');" > drush

# drush コマンドを実行可能にして /usr/local/bin に移動
chmod +x drush
mv drush /usr/local/bin

# Drupal をダウンロード
drush -y dl drupal-7 --destination=/var/www --drupal-project-rename=html

# アップロードされたファイルを保存するためのディレクトリを用意
mkdir /var/www/html/sites/default/files /var/www/html/sites/default/private

# Drupal サイトのルートディレクトリに移動して drush コマンドに備える
cd /var/www/html

# Drupal をインストール
drush -y si\
  --db-url=mysql://root@localhost/drupal\
  --locale=ja\
  --account-name=@@@user_name@@@\
  --account-pass=@@@password@@@\
  --account-mail=@@@mail@@@\
  --site-name=@@@site_name@@@

# アップデートマネージャーモジュールを有効化
drush -y en update

# Drupal をローカライズするためのモジュールを有効化
drush -y en locale

# 日本のロケール設定
drush -y vset site_default_country JP

# 日本語をデフォルトの言語として追加
# drush_language モジュールも使えるが、スタートアップスクリプトでは上手く
# 動かないので eval を使う
drush eval "locale_add_language('ja', 'Japanese', '日本語');"
drush eval '$langs = language_list(); variable_set("language_default", $langs["ja"])'

# 最新の日本語ファイルを取り込むモジュールをダウンロードしてインストール
drush -y dl l10n_update
drush -y en l10n_update

# 最新の日本語情報を取得してインポート
drush l10n-update-refresh
drush l10n-update

# Drupal ディレクトリの所有者を apche に変更
chown -R apache: /var/www/html

# Drupal のクロンタスクを作成し一時間に一度の頻度で回す
cat << EOS > /etc/cron.hourly/drupal
#!/bin/bash
/usr/local/bin/drush -r /var/www/html cron
EOS
chmod 755 /etc/cron.hourly/drupal

# Apache を自動起動する
systemctl enable httpd.service

# Apache を起動する
systemctl start httpd.service

# ファイアウォールに対し http プロトコルでのアクセスを許可する
firewall-cmd --add-service=http
