sudo sysctl -w net.mptcp.enabled=0
echo 'net.mptcp.enabled = 0' | sudo tee /etc/sysctl.d/99-disable-mptcp.conf
sysctl net.mptcp.enabled