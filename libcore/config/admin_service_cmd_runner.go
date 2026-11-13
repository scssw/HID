//go:build !windows

package config

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func ExecuteCmd(executablePath string, background bool, args ...string) (string, error) {
	cwd := filepath.Dir(executablePath)
	if appimage := os.Getenv("APPIMAGE"); appimage != "" {
		executablePath = appimage
		if !background {
			return "Fail", fmt.Errorf("Appimage cannot have service")
		}
	}

	fullArgs := append([]string{executablePath}, args...)
	quotedCmd := fmt.Sprintf("'%s'", strings.ReplaceAll(executablePath, "'", "'\\''"))
	for _, a := range args {
		quotedCmd += fmt.Sprintf(" '%s'", strings.ReplaceAll(a, "'", "'\\''"))
	}
	if background {
		quotedCmd = "nohup " + quotedCmd + " > /tmp/hiddify-tunnel.log 2>&1 < /dev/null &"
	} else {
		quotedCmd += " > /tmp/hiddify-tunnel-install.log 2>&1"
	}
	osaScript := fmt.Sprintf(`do shell script "%s" with prompt "Hiddify needs administrator permission to install the VPN tunnel service. Please enter your administrator password." with administrator privileges`, strings.ReplaceAll(quotedCmd, `"`, `\"`))

	var commands [][]string
	if runtime.GOOS == "darwin" {
		commands = [][]string{
			{"osascript", "-e", osaScript},
		}
	} else {
		commands = [][]string{
			{"pkexec", executablePath},
			{"gksu", executablePath},
			{"xterm", "-e", "sudo", executablePath, strings.Join(args, " ")},
			append([]string{"sudo"}, fullArgs...),
		}
	}

	var err error
	var cmd *exec.Cmd
	var lastOut []byte
	for _, command := range commands {
		cmd = exec.Command(command[0], command[1:]...)
		cmd.Dir = cwd
		fmt.Printf("Running command: %v\n", command)
		if background && command[0] != "osascript" {
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			err = cmd.Start()
		} else {
			lastOut, err = cmd.CombinedOutput()
			if len(lastOut) > 0 {
				fmt.Printf("Command output: %s\n", string(lastOut))
			}
		}
		if err == nil {
			return "Ok", nil
		}
	}

	return "", fmt.Errorf("Error executing run as root shell command: %v (output: %s)", err, strings.TrimSpace(string(lastOut)))
}
