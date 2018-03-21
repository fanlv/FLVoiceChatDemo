
AppName=FLVoiceChatDemo
rm -rf $AppName
mkdir $AppName
mkdir $AppName/Payload
cp -r $AppName.app $AppName/Payload/$AppName.app
cp Icon.png $AppName/iTunesArtwork
cd $AppName
zip -r $AppName.ipa Payload iTunesArtwork

exit 0