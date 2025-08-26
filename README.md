Note that the following steps will only work for a RHEL based distro like Fedora or CentOS

Step-1> Make a folder with all the files in it. Name it defensys-2.0

Step-2> Make a tarball and move it to the SOURCES directory
        tar -czvf defensys-2.0.tar.gz defensys-1.0/
        mv defensys-2.0.tar.gz ~/rpmbuild/SOURCES/
        
Step-3> Create a spec file defensys.spec at ~/rpmbuild/SPECS/ 

Step-4> Build the RPM with rpmbuild -ba ~/rpmbuild/SPECS/defenys.spec and install it with sudo dnf install ~/rpmbuild/RPMS/noarch/defenys-1.0-1.el9.noarch.rpm (You may need to adjust the name depending on your system)
