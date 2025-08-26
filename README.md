Note that the following steps will only work for a RHEL based distro like Fedora or CentOS

Step-1> Make a folder with all the files in it. Name it defensys-2.0
Step-2> Make a tarball and move it to the SOURCES directory
        tar -czvf defensys-2.0.tar.gz defensys-1.0/
        mv defensys-2.0.tar.gz ~/rpmbuild/SOURCES/
Step-3> Create a spec file defensys.spec at ~/rpmbuild/SPECS/ with the following content

        Name:           defenys
Version:        1.0
Release:        1%{?dist}
Summary:        A comprehensive system hardening toolkit for Linux.
License:        MIT
URL:            https://github.com/yourusername/defenys
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch

%description
Defenys is a command-line tool that automates security hardening
and compliance auditing on Linux and RHEL systems. It integrates
native tools like SELinux, Firewalld, and OpenSCAP to improve
system security posture.

%prep
%setup -q

%build
# No compilation needed for shell scripts

%install
# Create the installation directories
mkdir -p %{buildroot}/usr/local/bin
mkdir -p %{buildroot}/opt/%{name}/scripts
mkdir -p %{buildroot}/var/log

# Copy the main executable script to a standard bin path
install -m 0755 defensys.sh %{buildroot}/usr/local/bin/%{name}

# Copy the individual scripts to a project-specific directory
install -m 0755 *.sh %{buildroot}/opt/%{name}/scripts/

# Create an empty log file that will be managed by the scripts
touch %{buildroot}/var/log/security_hardening.log
chmod 644 %{buildroot}/var/log/security_hardening.log

%files
/usr/local/bin/%{name}
/opt/%{name}/scripts
%config(noreplace) /var/log/security_hardening.log

%changelog
* Tue Aug 26 2025 Your Name <youremail@example.com> - 1.0-1
- Initial release of the Defenys system hardening toolkit.


Step-4> Build the RPM with rpmbuild -ba ~/rpmbuild/SPECS/defenys.spec and install it with sudo dnf install ~/rpmbuild/RPMS/noarch/defenys-1.0-1.el9.noarch.rpm (You may need to adjust the name depending on your system)
