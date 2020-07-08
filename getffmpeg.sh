#!/bin/bash
curl https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz --output ffmpeg-git-amd64-static.tar.xz
tar xvf ffmpeg-git-amd64-static.tar.xz
rm -f ffmpeg-git-64bit-static.tar.xz
cd ffmpeg-git-*-amd64-static
#sudo mv ff* /usr/bin
sudo install -m 755 ff* /usr/bin
echo $PWD
cd ..
rm -rf ffmpeg-git-*

