# Tool that I can use to quickly open all files of a specific type in the mod, using the text editor Kate
# Designed for Kubuntu, will not work in Windows and probably won't work in other flavours of Linux unless Kate is installed
# Meant to be manually modified to be used
# (make sure Kate is already open before using this)
# -o -name ""
for file in `find . -type f -name "*.monstertype" -o -name "*.lua"`; do
    kate $file
done
