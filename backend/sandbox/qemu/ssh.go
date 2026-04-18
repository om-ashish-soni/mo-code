package qemu

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"

	"golang.org/x/crypto/ssh"
)

// sshRun dials the guest over the host-forwarded SSH port, runs cmd, and
// returns stdout, stderr, exit code. Exit code is -1 if the channel couldn't
// be established (distinct from "command ran and exited non-zero").
func sshRun(ctx context.Context, cfg config, cmd string) (string, string, int, error) {
	client, err := sshDial(ctx, cfg)
	if err != nil {
		return "", "", -1, err
	}
	defer client.Close()

	sess, err := client.NewSession()
	if err != nil {
		return "", "", -1, fmt.Errorf("qemu ssh: new session: %w", err)
	}
	defer sess.Close()

	var stdout, stderr bytes.Buffer
	sess.Stdout = &stdout
	sess.Stderr = &stderr

	// Respect ctx cancellation by closing the session asynchronously.
	done := make(chan error, 1)
	go func() { done <- sess.Run(cmd) }()

	select {
	case <-ctx.Done():
		_ = sess.Signal(ssh.SIGKILL)
		_ = sess.Close()
		return stdout.String(), stderr.String(), -1, ctx.Err()
	case runErr := <-done:
		if runErr == nil {
			return stdout.String(), stderr.String(), 0, nil
		}
		var exitErr *ssh.ExitError
		if errors.As(runErr, &exitErr) {
			return stdout.String(), stderr.String(), exitErr.ExitStatus(), nil
		}
		var missingErr *ssh.ExitMissingError
		if errors.As(runErr, &missingErr) {
			// Remote closed without reporting status — usually a poweroff kick.
			return stdout.String(), stderr.String(), -1, nil
		}
		return stdout.String(), stderr.String(), -1, fmt.Errorf("qemu ssh run: %w", runErr)
	}
}

// sshDial establishes an SSH connection to the guest. Respects ctx for the
// underlying TCP dial.
func sshDial(ctx context.Context, cfg config) (*ssh.Client, error) {
	sshCfg := &ssh.ClientConfig{
		User: cfg.SSHUser,
		Auth: []ssh.AuthMethod{
			ssh.Password(cfg.SSHPassword),
		},
		// Loopback-only port forward to a disposable guest. Host-key pinning
		// would require baking a known host key into the image and shipping
		// it with the APK; the risk model (127.0.0.1 user-mode net) does not
		// justify the complexity for v1.
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), //nolint:gosec // loopback-only
		Timeout:         5 * 1e9,                      // 5s, ssh internal timeout
	}

	addr := net.JoinHostPort("127.0.0.1", strconv.Itoa(cfg.SSHPort))

	var d net.Dialer
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("qemu ssh: dial %s: %w", addr, err)
	}

	sshConn, chans, reqs, err := ssh.NewClientConn(conn, addr, sshCfg)
	if err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("qemu ssh: handshake: %w", err)
	}
	return ssh.NewClient(sshConn, chans, reqs), nil
}
