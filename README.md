# How to

##### branch off from the upstream tag corresponding to the latest package version

```shell
$ cd plasma-login-manager
$ git checkout master
$ ./create-branch.sh
```

##### Sort out dependencies

```shell
$ sudo group install "development-tools"
$ sudo dnf builddep plasma-login-manager
```


##### Scaffold an RPM working directory

```shell
$ rm -rf /path/to/build/directory
$ mkdir /path/to/build/directory
$ env HOME=/path/to/build/directory rpmdev-setuptree

$ cp plasma-login-manager.spec /path/to/build/directory/rpmbuild/SPECS/
$ spectool -C /path/to/build/directory/rpmbuild/SOURCES/ -g plasma-login-manager.spec
$ spectool --list-files --all plasma-login-manager.spec
```

##### Compile and install `plasma-login-manager`

```shell
$ env HOME=/path/to/build/directory rpmbuild -bc plasma-login-manager.spec
$ sudo dnf reinstall /path/to/output.rpm
```
