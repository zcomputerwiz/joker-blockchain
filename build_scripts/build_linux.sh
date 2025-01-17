#!/bin/bash

# Need to keep the name and productName value is same in package.json file. Other wise will be error on the last step (electron-packager)
# Into direction path: ~/joker-blockchain/build_scripts
# sudo sh build_linux.sh amd64
# sudo sh build_linux.sh arm64

. ../activate

set -e

if [ ! "$1" ]; then
  echo "This script requires either amd64 of arm64 as an argument"
	exit 1
elif [ "$1" = "amd64" ]; then
	PLATFORM="$1"
	REDHAT_PLATFORM="x86_64"
	DIR_NAME="joker-blockchain-linux-x64"
else
	PLATFORM="$1"
	DIR_NAME="joker-blockchain-linux-arm64"
fi

pip install setuptools_scm
pip install requests
# The environment variable JOKER_INSTALLER_VERSION needs to be defined
# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG
JOKER_INSTALLER_VERSION=$(python installer-version.py)

if [ ! "$JOKER_INSTALLER_VERSION" ]; then
	echo "WARNING: No environment variable JOKER_INSTALLER_VERSION set. Using 0.0.0."
	JOKER_INSTALLER_VERSION="0.0.0"
fi

JOKER_INSTALLER_VERSION="1.0.1"

echo "Joker Installer Version is: $JOKER_INSTALLER_VERSION"

echo "Installing npm and electron packagers"
npm install electron-packager -g
npm install electron-installer-debian -g
npm install electron-installer-redhat -g

echo "Create dist/"
rm -rf dist
mkdir dist

echo "Create executables with pyinstaller"
pip install pyinstaller==4.2
SPEC_FILE=$(python -c 'import joker; print(joker.PYINSTALLER_SPEC_PATH)')
pyinstaller --log-level=INFO "$SPEC_FILE"
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "pyinstaller failed!"
	exit $LAST_EXIT_CODE
fi

cp -r dist/daemon ../joker-blockchain-gui
cd .. || exit
cd joker-blockchain-gui || exit

echo "npm build"
npm install
npm audit fix
npm run build
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "npm run build failed!"
	exit $LAST_EXIT_CODE
fi

electron-packager . joker-blockchain --asar.unpack="**/daemon/**" --platform=linux \
--icon=src/assets/img/Joker.icns --overwrite --app-bundle-id=net.joker.blockchain \
--appVersion=$JOKER_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-packager failed!"
	exit $LAST_EXIT_CODE
fi

mv $DIR_NAME ../build_scripts/dist/
cd ../build_scripts || exit

echo "Create joker-$JOKER_INSTALLER_VERSION.deb"
rm -rf final_installer
mkdir final_installer
electron-installer-debian --src dist/$DIR_NAME/ --dest final_installer/ \
--arch "$PLATFORM" --options.version $JOKER_INSTALLER_VERSION
LAST_EXIT_CODE=$?
if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	echo >&2 "electron-installer-debian failed!"
	exit $LAST_EXIT_CODE
fi

if [ "$REDHAT_PLATFORM" = "x86_64" ]; then
	echo "Create joker-blockchain-$JOKER_INSTALLER_VERSION.rpm"
  electron-installer-redhat --src dist/$DIR_NAME/ --dest final_installer/ \
  --arch "$REDHAT_PLATFORM" --options.version $JOKER_INSTALLER_VERSION \
  --license ../LICENSE
  LAST_EXIT_CODE=$?
  if [ "$LAST_EXIT_CODE" -ne 0 ]; then
	  echo >&2 "electron-installer-redhat failed!"
	  exit $LAST_EXIT_CODE
  fi
fi

ls final_installer/
