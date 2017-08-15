#!/bin/bash

# 実行例： bash ~/android/build.sh ~/android/aicp maple aicp -s -u -x

# YOUR_ACCESS_TOKEN には https://www.pushbullet.com/#settings/account から取得したトークンを使用
PUSHBULLET_TOKEN=YOUR_ACCESS_TOKEN

# ツイート用のハッシュタグを必要に応じて変えてください
TWEET_TAG="homuraBuild"

# 実行時の引数が正しいかチェック
if [ $# -lt 2 ]; then
	echo "指定された引数は$#個です。" 1>&2
	echo "仕様: $CMDNAME [ビルドディレクトリの絶対パス] [ターゲット] [ROMの種類] [-t] [-s] [-c] [-u] [-x]" 1>&2
	echo "ROMの種類はlineageかaicpを指定してください。" 1>&2
	echo "ツイートは-t、repo syncは-s、make cleanは-c、非公式ビルドは-u、Sony Xperia向けのビルドは-xを指定してください。" 1>&2
	echo "ログは自動的に記録されます。" 1>&2
	exit 1
fi

builddir=$1
device=$2
romtype=$3
shift 3

while getopts :tscux argument; do
case $argument in
	t) tweet=true ;;
	s) sync=true ;;
	c) clean=true ;;
	u) unofficial=true ;;
	x) xperia=true ;;
	*) echo "正しくない引数が指定されました。" 1>&2
	   exit 1 ;;
esac
done

mkdir -p $builddir/../log/success $builddir/../log/fail ~/rom

# gdrive https://github.com/prasmussen/gdrive を使います
# golang をインストールした上でREADMEの Download からバイナリ落として来る
# 適当に ~/gdrive あたりに置いて chmod 755 gdrive
# ~/gdrive list で初回はWebからトークン取得してフォルダのIdを取る
# フォルダ名は「AICP-[ターゲット]」にしてください。 (例： AICP-maple)
# 用法: ~/gdrive upload -p <フォルダのId> <アップロードするファイル名>

# GドライブのフォルダIDを取得
gfolderlist=`gdrive list --max 1 --name-width 0 --query "trashed = false and 'me' in owners and mimeType = 'application/vnd.google-apps.folder' and name contains 'AICP-${device}'"`
gfolderid=`echo ${gfolderlist} | sed "s@Id Name Type Size Created \([a-zA-Z0-9]*\).*@\1@"`

# Gドライブの上記で取得したフォルダ内のChangelog.txtのIDを取得
gfilelist=`gdrive list --max 1 --name-width 0 --query "trashed = false and 'me' in owners and '${gfolderid}' in parents and name contains 'Changelog.txt'"`
gfileid=`echo ${gfilelist} | sed "s@Id Name Type Size Created \([a-zA-Z0-9]*\).*@\1@"`

cd $builddir

# repo sync
if [ "$sync" = "true" ]; then
	if [ "$xperia" = "true" ]; then
		bash ~/repo-update-from-origin/repo_update.sh $builddir
	else
		repo sync -j8 -c -f --force-sync --no-clone-bundle
	fi
	echo -e "\n"
fi

# make clean
if [ "$clean" = "true" ]; then
	make clean
	echo -e "\n"
fi

# 現在日時取得、ログのファイル名設定
starttime=$(date '+%Y/%m/%d %T')
filetime=$(date '+%Y-%m-%d_%H-%M-%S')
filename="${filetime}_${romtype}_${device}.log"

# CMやRRの場合、吐き出すzipのファイル名はUTC基準での日付なので注意
zipdate=$(date -u '+%Y%m%d')

# unofficialだとbreakfastでエラーがでる?ので対処
if [ "$unofficial" = "true" ]; then
	cp -a $builddir/device/*/$device/aicp_$device.mk $builddir/vendor/$romtype/products/$device.mk
	source build/envsetup.sh
else
	source build/envsetup.sh
	breakfast $device
fi

# ツイート用のROM情報の設定をする
if [ "$romtype" = lineage ]; then
	vernum="$(get_build_var PRODUCT_VERSION_MAJOR).$(get_build_var PRODUCT_VERSION_MINOR)"
	source="LineageOS ${vernum}"
	short="${source}"
	zipname="lineage-$(get_build_var LINEAGE_VERSION)"
	newzipname="lineage-${vernum}-${filetime}-$(get_build_var CM_BUILDTYPE)-$(get_build_var CM_BUILD)"
elif [ "$romtype" = aicp ]; then
        vernum="$(get_build_var AICP_BRANCH)-$(get_build_var VERSION)"
        source="AICP-${vernum}"
        short="${source}"
        zipname="$(get_build_var AICP_VERSION)"
        newzipname="aicp_${device}_${vernum}-$(get_build_var AICP_BUILDTYPE)-${filetime}"
else
# 一応対処するけど他ROMについては上記を参考にちゃんと書いてもらわないと後がめんどい
	source=$builddir
	short="${source}"
	zipname="*"
	newzipname="${zipname}"
fi

# 開始時のツイート
if [ "$tweet" = "true" ]; then
	twstart=$(echo -e "${device} 向け ${source} のビルドを開始します。 \n\n$starttime #${TWEET_TAG}")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twstart"
fi

# ビルド
if [ "$unofficial" = "true" ]; then
	brunch aicp_$device-userdebug 2>&1 | tee "../log/$filename"
else
	mka bacon 2>&1 | tee "../log/$filename"
fi

if [ $(echo ${PIPESTATUS[0]}) -eq 0 ]; then
	ans=1
	statusdir="success"
	endstr=$(tail -n 3 "../log/$filename" | tr -d '\n' | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | sed 's/#//g' | sed 's/make completed successfully//g' | sed 's/^[ ]*//g')
	statustw="${zipname} のビルドに成功しました！"
else
	ans=0
	statusdir="fail"
	endstr=$(tail -n 3 "../log/$filename" | tr -d '\n' | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | sed 's/#//g' | sed 's/make failed to build some targets//g' | sed 's/^[ ]*//g')
	statustw="${device} 向け ${source} のビルドに失敗しました…"
fi

cd ..

echo -e "\n"

# 結果のツイート
if [ "$tweet" = "true" ]; then
	endtime=$(date '+%Y/%m/%d %H:%M:%S')
	twfinish=$(echo -e "$statustw\n\n$endstr\n\n$endtime #${TWEET_TAG}")
	perl ~/oysttyer/oysttyer.pl -ssl -status="$twfinish" -autosplit=cut
fi

# Pushbullet APIを使ってプッシュ通知も投げる。文言は適当に
if [ "${PUSHBULLET_TOKEN}" != "YOUR_ACCESS_TOKEN" ]; then
	pbtitle=$(echo -e "${statusdir}: Build ${short} for ${device}")
	pbbody=$(cat -v "log/$filename" | tail -n 3 | tr -d '\n' | cut -d "#" -f 5-5 | cut -c 2-)

	curl -u ${PUSHBULLET_TOKEN}: -X POST \
	  https://api.pushbullet.com/v2/pushes \
	  --header "Content-Type: application/json" \
	  --data-binary "{\"type\": \"note\", \"title\": \"${pbtitle}\", \"body\": \"${pbbody}\"}"
fi

# ログを移す
mv -v log/$filename log/$statusdir/

echo -e "\n"

# ビルドが成功していればGoogle ドライブに上げる
if [ $ans -eq 1 ]; then
	mv -v $builddir/out/target/product/$device/${zipname}.zip ${newzipname}.zip
	gdrive upload -p ${gfolderid} --share ${newzipname}.zip
	gdrive update ${gfileid} $builddir/out/target/product/$device/Changelog.txt
	
	mkdir -p ~/rom/$device
	
	mv -v ${newzipname}.zip ~/rom/$device/${newzipname}.zip
	mv -v $builddir/out/target/product/$device/${zipname}.zip.md5sum ~/rom/$device/${newzipname}.zip.md5sum

	echo -e "\n"
fi
