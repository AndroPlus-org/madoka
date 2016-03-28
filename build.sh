#!/bin/bash

# YOUR_ACCESS_TOKEN には https://www.pushbullet.com/#settings/account から取得したトークンを使用
PUSHBULLET_TOKEN=YOUR_ACCESS_TOKEN

# 実行時の引数が正しいかチェック
if [ $# -ne 5 ]; then
	echo "指定された引数は$#個です。" 1>&2
	echo "仕様: $CMDNAME [ビルドディレクトリ] [ターゲット] [ツイート可否] [repo sync可否] [make clean可否]" 1>&2
	echo "ツイート、repo sync、make cleanの可否は1(有効)か0(無効)で選択してください。" 1>&2
	echo "ログは自動的に記録されます。" 1>&2
	exit 1
fi

builddir=$1
device=$2

cd ../$builddir

# repo sync
if [ $4 -eq 1 ]; then
	repo sync -j8 --force-sync
	echo -e "\n"
fi

# make clean
if [ $5 -eq 1 ]; then
	make clean
	echo -e "\n"
fi

# 現在日時取得、ログのファイル名設定
starttime=$(date '+%Y/%m/%d %T')
filetime=$(date '+%Y-%m-%d_%H-%M-%S')
filename="${filetime}_${builddir}_${device}.log"

# CMやRRの場合、吐き出すzipのファイル名はUTC基準での日付なので注意。
zipdate=$(date -u '+%Y%m%d')
# AOKPは他と違う上にホストのタイムゾーン基準での日時です
aokpdate=$(date '+%Y-%m-%d_%H%M')

source build/envsetup.sh
breakfast $device

# ディレクトリ名からツイート用のROM情報の設定をする
if [ $builddir = cm13 ]; then
	source="CyanogenMod 13.0"
	zipname=$(get_build_var CM_VERSION)
elif [ $builddir = rr ]; then
	vernum=$(get_build_var CM_VERSION | cut -c21-26)
	source="ResurrectionRemix ${vernum}"
	zipname=$(get_build_var CM_VERSION)
elif [ $builddir = aokp ]; then
	source="AOKP (Marshmallow)"
	zipname="aokp_${device}_mm_unofficial_${aokpdate}"
else
	source=$builddir
	zipname="*"
fi

# 開始時のツイート
if [ $3 -eq 1 ]; then
	twstart=$(echo -e "${device} 向け ${source} のビルドを開始します。 \n\n$starttime #mashiroBuild")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twstart"
fi

# ビルド
mka bacon 2>&1 | tee "../log/$filename"

if [ $(echo ${PIPESTATUS[0]}) -eq 0 ]; then
	ans=1
	statusdir="success"
else
	ans=0
	statusdir="fail"
fi

cd ..
mv -v log/$filename log/$statusdir/

echo -e "\n"

# 結果のツイート
	endstr=$(cat -v "log/$statusdir/$filename" | tail -n 3 | tr -d '\n' | cut -d "#" -f 5-5 | cut -c 2-)
if [ $3 -eq 1 ]; then
	endtime=$(date '+%Y/%m/%d %H:%M:%S')
	if [ $ans -eq 1 ]; then
		twfinish=$(echo -e "${zipname} のビルドに成功しました！\n\n$endstr\n\n$endtime #mashiroBuild")
	else
		twfinish=$(echo -e "${device} 向け ${source} のビルドに失敗しました…\n\n$endstr\n\n$endtime #mashiroBuild")
	fi

	perl ~/oysttyer/oysttyer.pl -ssl -status="$twfinish" -autosplit=cut
fi

# Pushbullet APIを使ってプッシュ通知も投げる。文言は適当に
endpush="build for ${device} #mashiroBuild"
curl -u ${PUSHBULLET_TOKEN}: -X POST \
  https://api.pushbullet.com/v2/pushes \
  --header "Content-Type: application/json" \
  --data-binary "{\"type\": \"note\", \"title\": \"${endpush}\", \"body\": \"${endstr}\"}"

echo -e "\n"

# ビルドが成功してればMEGAに上げつつ ~/rom に移動しておく
# megaput は https://megatools.megous.com から megatools をインストール、
# man を参照の上 ~/.megarc にユーザ名とパスワードを記載して使用
if [ $ans -eq 1 ]; then

	# $device に該当するフォルダが無い場合に備えてアップロード先はファイル名ごと指定
	megaput $builddir/out/target/product/$device/${zipname}.zip --path /Root/mashiro/$device/${zipname}.zip

	mkdir -p ~/rom/$device

	mv -v $builddir/out/target/product/$device/${zipname}.zip ~/rom/$device/
	mv -v $builddir/out/target/product/$device/${zipname}.zip.md5sum ~/rom/$device/

	echo -e "\n"

fi
