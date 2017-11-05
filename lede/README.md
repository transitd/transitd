# LEDE/OpenWrt Image Build Instructions

```
$ git clone -b v17.01.4 https://git.lede-project.org/source.git lede
$ git clone --depth=1 git://github.com/transitd/transitd.git
$ cp build/* build/.* lede/
$ cd lede
$ ./lnum.nuke.sh
$ ./feedmagic.sh
$ make -j 10
```
