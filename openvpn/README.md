OpenVPN user/client authentication process
==========================================

Authentication
--------------
OpenVPN server can verify clients by his credentials such as login name and password. This options is disable by default. 
To achieve this you have to change configuration and prepare script similar to openvpn-auth.sh.

How it works
------------
While authentication process OpenVPN server get credentials from client. In the next step execute your script and pass it credentials. Your script have to verify credentials and return to server authorization result. 

How do it
---------
* Make client credentials list in file /etc/openvpn/auth. Each line contains login name and hash from password.
Example /etc/openvpn/auth
```
	Client1 948fe603f61dc036b5c596dc09fe3ce3f3d30dc90f024c85f3c82db2ccab679d
	Client2 3f455143e75d1e7fd659dea57023496da3bd9f2f8908d1e2ac32641cd819d3e3
	Smith   3f455143e75d1e7fd659dea57023496da3bd9f2f8908d1e2ac32641cd819d3e3
```
Use command below to easy append to file /etc/openvpn/auth
```shell
read -p "Login:" Login;read -p "Password:" Password;[ -n "$Login" ] && [ -n "$Password" ] && echo -e "$Login\t$(echo $Password|openssl dgst -sha256|cut -f 2 -d ' ')">>/etc/openvpn/auth
```

* Change OpenVPN server configuration. You can use two method to pass credentials to script. First via file ad second via environment variable.
  * If you pass credentials via file (is more secure), you have to add or set two parameters in /etc/config/openvpn server configuration file:
```
	option 'script_security' '2'
	option 'auth_user_pass_verify' '/bin/openvpn-auth.sh via-file'
```
  * if you choose second method to pass credentials via environment variables you have to add or set two parameters in file /etc/config/openvpn
```
	option 'script_security' '3'
	option 'auth_user_pass_verify' '/bin/openvpn-auth.sh via-env'
```
* To enable authorization by credentials on client-side you have to add 'auth-user-pass' option in client config file.
	
* Put content of openvpn-auth.sh to /bin/openvpn-auth.sh and make executable chmod +x /bin/openvpn-auth.sh 
