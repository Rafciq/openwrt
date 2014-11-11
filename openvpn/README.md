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
	Client1 d577273ff885c3f84dadb8578bb41399
	Client2 f5ac8127b3b6b85cdc13f237c6005d80
	Smith   9954987819a9e85b2aae8c04803f6b26
```
Use command below to easy append to file /etc/openvpn/auth
```shell
read -p "Login:" Login;read -p "Password:" Password;[ -n "$Login" ] && [ -n "$Password" ] && echo -e "$Login\t$(echo $Password|md5sum|cut -f 1 -d ' ')">>/etc/openvpn/auth
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
