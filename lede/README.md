# LEDE/OpenWrt Image Build Instructions

We are going to need to clone LEDE and transitd repos,
```
$ git clone -b v17.01.4 https://git.lede-project.org/source.git lede
$ git clone --depth=1 git://github.com/transitd/transitd.git
```
Then, we need to copy some build helper files into the LEDE folder,
```
$ cp transitd/lede/build/* transitd/lede/build/.* lede/
```
Now, `cd` into LEDE folder and begin the process,
```
$ cd lede
```
We need to nuke the lnum patch set which is a breaking change to Lua that will prevent transitd from working,
```
$ ./lnum.nuke.sh
```
The feed magic script prioritizes the [transitd feed packages](https://github.com/transitd/lede-packages) over other LEDE packages and also provides some extra dependency packages.
```
$ ./feedmagic.sh
```
Now issue the build command,
```
$ make -j 10
```
