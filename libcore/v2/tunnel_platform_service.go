package v2

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/kardianos/service"
)

var logger service.Logger

type hiddifyNext struct{}

var port int = 18020

func (m *hiddifyNext) Start(s service.Service) error {
	_, err := StartTunnelGrpcServer(fmt.Sprintf("127.0.0.1:%d", port))
	return err
}

func (m *hiddifyNext) Stop(s service.Service) error {
	_, err := Stop()
	if err != nil {
		return nil
	}
	return nil
}

func getCurrentExecutableDirectory() string {
	executablePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Dir(executablePath)
}

func StartTunnelService(goArg string) (int, string) {
	if runtime.GOOS == "darwin" {
		return handleDarwinTunnelService(goArg)
	}

	tunnelWorkDir := filepath.Join(os.TempDir(), "hiddify-tunnel")
	_ = os.MkdirAll(tunnelWorkDir, 0o755)
	if coreLogFactory == nil {
		if err := Setup(tunnelWorkDir, tunnelWorkDir, os.TempDir(), 0, true); err != nil {
			log.Printf("Tunnel Setup error: %v", err)
		}
	}
	svcConfig := &service.Config{
		Name:        "HiddifyTunnelService",
		DisplayName: "Hiddify Tunnel Service",
		Arguments:   []string{"tunnel", "run"},
		Description: "This is a bridge for tunnel",
		Option: map[string]interface{}{
			"RunAtLoad":        true,
			"WorkingDirectory": getCurrentExecutableDirectory(),
		},
	}

	prg := &hiddifyNext{}
	s, err := service.New(prg, svcConfig)
	if err != nil {
		return 1, fmt.Sprintf("Error: %v", err)
	}

	if len(goArg) > 0 && goArg != "run" {
		return control(s, goArg)
	}

	logger, err = s.Logger(nil)
	if err != nil {
		log.Printf("Error: %v", err)
	}
	err = s.Run()
	if err != nil {
		logger.Error(err)
		return 3, fmt.Sprintf("Error: %v", err)
	}
	return 0, ""
}

func handleDarwinTunnelService(goArg string) (int, string) {
	switch goArg {
	case "run":
		return runDarwinDirectTunnelServer()
	case "install":
		return handleDarwinTunnelInstall()
	case "uninstall":
		return handleDarwinTunnelUninstall()
	case "start":
		return handleDarwinTunnelStart()
	case "stop":
		return handleDarwinTunnelStop()
	default:
		return 1, fmt.Sprintf("unsupported action on darwin: %s", goArg)
	}
}

func runDarwinDirectTunnelServer() (int, string) {
	tunnelWorkDir := filepath.Join(os.TempDir(), "hiddify-tunnel")
	_ = os.MkdirAll(tunnelWorkDir, 0o755)
	if coreLogFactory == nil {
		if err := Setup(tunnelWorkDir, tunnelWorkDir, os.TempDir(), 0, true); err != nil {
			log.Printf("Darwin tunnel Setup error: %v", err)
		}
	}
	server, err := StartTunnelGrpcServer(fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		log.Printf("Darwin tunnel StartTunnelGrpcServer error: %v", err)
		return 1, fmt.Sprintf("Error starting gRPC server: %v", err)
	}
	log.Printf("Darwin tunnel gRPC server listening on 127.0.0.1:%d", port)

	sigChan := make(chan os.Signal, 2)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	sig := <-sigChan
	log.Printf("Darwin tunnel service received signal: %v, shutting down...", sig)

	if server != nil {
		server.GracefulStop()
	}
	_, _ = Stop()
	return 0, "Tunnel Service Stopped"
}

func handleDarwinTunnelInstall() (int, string) {
	exePath, err := os.Executable()
	if err != nil {
		return 1, fmt.Sprintf("failed to get executable path: %v", err)
	}
	realExePath, err := filepath.EvalSymlinks(exePath)
	if err == nil {
		exePath = realExePath
	}

	targetBin := exePath
	appSupportDir := "/Library/Application Support/Hiddify"
	if err := os.MkdirAll(appSupportDir, 0o755); err == nil {
		destCli := filepath.Join(appSupportDir, "HiddifyCli")
		_ = os.Remove(destCli)
		if copyFile(exePath, destCli) == nil {
			_ = os.Chmod(destCli, 0o755)
			_ = exec.Command("chown", "root:wheel", destCli).Run()
			targetBin = destCli
		}
	}

	plistPath := "/Library/LaunchDaemons/HiddifyTunnelService.plist"
	plistContent := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>HiddifyTunnelService</string>
	<key>ProgramArguments</key>
	<array>
		<string>%s</string>
		<string>tunnel</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>/tmp/hiddify-tunnel.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/hiddify-tunnel.log</string>
</dict>
</plist>
`, targetBin)

	// Clean up any stale instances
	_ = exec.Command("launchctl", "bootout", "system/HiddifyTunnelService").Run()
	_ = exec.Command("launchctl", "bootout", "system", plistPath).Run()
	_ = exec.Command("launchctl", "unload", plistPath).Run()
	_ = exec.Command("pkill", "-f", "HiddifyCli tunnel run").Run()

	// Write plist file and ensure system ownership & permissions
	_ = os.Remove(plistPath)
	if err := os.WriteFile(plistPath, []byte(plistContent), 0o644); err != nil {
		return 1, fmt.Sprintf("failed to write %s: %v", plistPath, err)
	}
	_ = os.Chmod(plistPath, 0o644)
	_ = exec.Command("chown", "root:wheel", plistPath).Run()

	// Enable and register via launchctl
	_ = exec.Command("launchctl", "enable", "system/HiddifyTunnelService").Run()
	_, bErr := exec.Command("launchctl", "bootstrap", "system", plistPath).CombinedOutput()
	if bErr != nil {
		_, _ = exec.Command("launchctl", "load", "-w", plistPath).CombinedOutput()
	}
	_ = exec.Command("launchctl", "kickstart", "-k", "-p", "system/HiddifyTunnelService").Run()
	_ = exec.Command("launchctl", "start", "HiddifyTunnelService").Run()

	// Wait up to 3 seconds for 18020 to listen
	started := false
	for i := 0; i < 20; i++ {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:18020", 150*time.Millisecond)
		if err == nil {
			conn.Close()
			started = true
			break
		}
		time.Sleep(150 * time.Millisecond)
	}

	// Fallback to nohup background daemon if launchctl didn't start it
	if !started {
		cmd := exec.Command("/bin/sh", "-c", fmt.Sprintf("nohup '%s' tunnel run > /tmp/hiddify-tunnel.log 2>&1 < /dev/null &", targetBin))
		_ = cmd.Run()
		for i := 0; i < 15; i++ {
			conn, err := net.DialTimeout("tcp", "127.0.0.1:18020", 200*time.Millisecond)
			if err == nil {
				conn.Close()
				started = true
				break
			}
			time.Sleep(200 * time.Millisecond)
		}
	}

	if !started {
		logTail := ""
		if data, err := os.ReadFile("/tmp/hiddify-tunnel.log"); err == nil {
			s := string(data)
			if len(s) > 300 {
				s = s[len(s)-300:]
			}
			logTail = s
		}
		return 2, fmt.Sprintf("HiddifyTunnelService installed but port 18020 not responding (log: %s)", logTail)
	}

	return 0, "Tunnel Service Installed and Running Successfully."
}

func handleDarwinTunnelUninstall() (int, string) {
	plistPath := "/Library/LaunchDaemons/HiddifyTunnelService.plist"
	_ = exec.Command("launchctl", "bootout", "system/HiddifyTunnelService").Run()
	_ = exec.Command("launchctl", "bootout", "system", plistPath).Run()
	_ = exec.Command("launchctl", "unload", plistPath).Run()
	_ = os.Remove(plistPath)
	_ = exec.Command("pkill", "-f", "HiddifyCli tunnel run").Run()
	_ = os.Remove("/Library/Application Support/Hiddify/HiddifyCli")
	return 0, "Tunnel Service Uninstalled Successfully."
}

func handleDarwinTunnelStop() (int, string) {
	_ = exec.Command("launchctl", "stop", "HiddifyTunnelService").Run()
	_ = exec.Command("pkill", "-f", "HiddifyCli tunnel run").Run()
	return 0, "Tunnel Service Stopped Successfully."
}

func handleDarwinTunnelStart() (int, string) {
	conn, err := net.DialTimeout("tcp", "127.0.0.1:18020", 200*time.Millisecond)
	if err == nil {
		conn.Close()
		return 0, "Tunnel Service Already Running."
	}
	plistPath := "/Library/LaunchDaemons/HiddifyTunnelService.plist"
	if _, err := os.Stat(plistPath); os.IsNotExist(err) {
		return handleDarwinTunnelInstall()
	}
	_ = exec.Command("launchctl", "kickstart", "-k", "-p", "system/HiddifyTunnelService").Run()
	_ = exec.Command("launchctl", "start", "HiddifyTunnelService").Run()
	for i := 0; i < 15; i++ {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:18020", 200*time.Millisecond)
		if err == nil {
			conn.Close()
			return 0, "Tunnel Service Started Successfully."
		}
		time.Sleep(200 * time.Millisecond)
	}
	return handleDarwinTunnelInstall()
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	defer out.Close()

	if _, err = io.Copy(out, in); err != nil {
		return err
	}
	return out.Sync()
}

func control(s service.Service, goArg string) (int, string) {
	dolog := false
	var err error
	status, serr := s.Status()
	if dolog {
		fmt.Printf("Current Status: %+v %+v!\n", status, serr)
	}
	switch goArg {
	case "uninstall":
		if status == service.StatusRunning {
			s.Stop()
		}
		if dolog {
			fmt.Printf("Tunnel Service Uninstalled Successfully.\n")
		}
		err = s.Uninstall()
	case "start":
		if status == service.StatusRunning {
			if dolog {
				fmt.Printf("Tunnel Service Already Running.\n")
			}
			return 0, "Tunnel Service Already Running."
		} else if status == service.StatusUnknown {
			s.Uninstall()
			s.Install()
			status, serr = s.Status()
			if dolog {
				fmt.Printf("Check status again: %+v %+v!", status, serr)
			}
		}
		if status != service.StatusRunning {
			err = s.Start()
		}
	case "install":
		s.Uninstall()
		err = s.Install()
		status, serr = s.Status()
		if dolog {
			fmt.Printf("Check Status Again: %+v %+v", status, serr)
		}
		if status != service.StatusRunning {
			err = s.Start()
		}
	case "stop":
		if status == service.StatusStopped {
			if dolog {
				fmt.Printf("Tunnel Service Already Stopped.\n")
			}
			return 0, "Tunnel Service Already Stopped."
		}
		err = s.Stop()
	default:
		err = service.Control(s, goArg)
	}
	if err == nil {
		out := fmt.Sprintf("Tunnel Service %sed Successfully.", goArg)
		if dolog {
			fmt.Printf(out)
		}
		return 0, out
	} else {
		out := fmt.Sprintf("Error: %v", err)
		if dolog {
			log.Printf(out)
		}
		return 2, out
	}
}
