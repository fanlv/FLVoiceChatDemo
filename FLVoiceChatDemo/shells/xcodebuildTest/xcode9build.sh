#!/bin/bash
#This is Test Shell file

PROJECT_NAME=FLVoiceChatDemo
CONFIGURATION=Debug
CURRENT_SHEME=FLVoiceChatDemo
BOUNDLE_VERSION=1.0.0
ROOT_PATH=/Users/fanlv/Documents/GitHub/FLVoiceChatDemo/FLVoiceChatDemo
SHELL_PATH=$ROOT_PATH/shells/xcodebuildTest


cd $ROOT_PATH


echo "================= 清除目录 - Start ================="
rm -rf $SHELL_PATH/build
echo "================= 清除目录 - End ================="

xcodebuild -list

echo "================= xcodebuild clean - Start ================="
xcodebuild clean  -project  ${PROJECT_NAME}.xcodeproj \
                  -scheme ${CURRENT_SHEME} \
                  -configuration ${CONFIGURATION} \

echo "================= xcodebuild clean - End ================="


echo "================= archive - Start ================="
xcodebuild archive -project ${PROJECT_NAME}.xcodeproj \
                   -scheme ${CURRENT_SHEME} \
                   -configuration ${CONFIGURATION} \
                   -archivePath $SHELL_PATH/build/${CURRENT_SHEME}.xcarchive \
                #    CODE_SIGN_IDENTITY="iPhone Distribution: Shenzhen City Xiao Haibei Technology Co. Ltd. (52C4UYZ32Z)" \
                #    PROVISIONING_PROFILE="a82db887-97d4-4b1e-b1b0-ec9e69b150ee"
echo "================= archive - End ================="

echo "================= xcodebuild -exportArchive - Start ================="

xcodebuild -exportArchive -archivePath "$SHELL_PATH/build/${CURRENT_SHEME}.xcarchive" -exportPath $SHELL_PATH/build -exportOptionsPlist $SHELL_PATH/ExportOptions.plist

echo "================= xcodebuild -exportArchive - End ================="

#xcodebuild clean -project FLVoiceChatDemo.xcodeproj -scheme FLVoiceChatDemo -configuration Debug
                #    CODE_SIGN_IDENTITY="iPhone Distribution: Shenzhen City Xiao Haibei Technology Co. Ltd. (52C4UYZ32Z)" \
                #    PROVISIONING_PROFILE="a82db887-97d4-4b1e-b1b0-ec9e69b150ee"

#/usr/bin/security cms -D -i /Users/fanlv/Library/MobileDevice/Provisioning\ Profiles/a82db887-97d4-4b1e-b1b0-ec9e69b150ee.mobileprovision