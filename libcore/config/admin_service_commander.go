package config

import (
	context "context"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	pb "github.com/hiddify/hiddify-core/hiddifyrpc"
	"github.com/sagernet/sing-box/option"
	dns "github.com/sagernet/sing-dns"
	grpc "google.golang.org/grpc"
)

const (
	serviceURL    = "http://localhost:18020"
	startEndpoint = "/start"
	stopEndpoint  = "/stop"
)

var tunnelServiceRunning = false

func isSupportedOS() bool {
	return runtime.GOOS == "windows" || runtime.GOOS == "linux" || runtime.GOOS == "darwin"
}

func ActivateTunnelService(opt HiddifyOptions) (bool, error) {
	tunnelServiceRunning = true
	res, err := startTunnelRequest(opt, true)
	fmt.Printf("Start Tunnel Result: %v, err=%v\n", res, err)
	if err != nil {
		tunnelServiceRunning = false
		return false, err
	}
	return res, nil
}

func DeactivateTunnelServiceForce() (bool, error) {
	return stopTunnelRequest()
}

func DeactivateTunnelService() (bool, error) {
	// if !isSupportedOS() {
	// 	return true, nil
	// }

	if tunnelServiceRunning {
		res, err := stopTunnelRequest()
		if err != nil {
			tunnelServiceRunning = false
		}
		return res, err
	} else {
		go stopTunnelRequest()
	}

	return true, nil
}

func startTunnelRequestWithFailover(opt HiddifyOptions, installService bool) {
	res, err := startTunnelRequest(opt, installService)
	fmt.Printf("Start Tunnel Result: %v\n", res)
	if err != nil {
		fmt.Printf("Start Tunnel Failed! Stopping core... err=%v\n", err)
		// StopAndAlert(pb.MessageType.MessageType_UNEXPECTED_ERROR, "Start Tunnel Failed! Stopping...")
	}
}

func isPortInUse(port string) bool {
	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+port, 300*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func startTunnelRequest(opt HiddifyOptions, installService bool) (bool, error) {
	if !isPortInUse("18020") {
		if installService {
			return runTunnelService(opt)
		}
		return false, fmt.Errorf("service is not running")
	}
	conn, err := grpc.Dial("127.0.0.1:18020", grpc.WithInsecure())
	if err != nil {
		log.Printf("did not connect: %v", err)
		return false, err
	}
	defer conn.Close()
	c := pb.NewTunnelServiceClient(conn)
	var res *pb.TunnelResponse
	for attempt := 0; attempt < 3; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		_, _ = c.Stop(ctx, &pb.Empty{})
		res, err = c.Start(ctx, &pb.TunnelStartRequest{
			Ipv6:                   opt.IPv6Mode != option.DomainStrategy(dns.DomainStrategyUseIPv4),
			ServerPort:             int32(opt.InboundOptions.MixedPort),
			StrictRoute:            opt.InboundOptions.StrictRoute,
			EndpointIndependentNat: true,
			Stack:                  opt.InboundOptions.TUNStack,
		})
		cancel()
		if err == nil {
			break
		}
		<-time.After(300 * time.Millisecond)
	}
	if err != nil {
		log.Printf("could not greet: %+v %+v", res, err)

		if installService {
			ExitTunnelService()
			return runTunnelService(opt)
		}
		return false, err
	}
	if res != nil && res.Message != "OK" {
		log.Printf("tunnel service start returned non-OK: %+v", res)
		return false, fmt.Errorf("tunnel start failed: %s", res.Message)
	}

	return true, nil
}

func stopTunnelRequest() (bool, error) {
	conn, err := grpc.Dial("127.0.0.1:18020", grpc.WithInsecure())
	if err != nil {
		log.Printf("did not connect: %v", err)
		return false, err
	}
	defer conn.Close()
	c := pb.NewTunnelServiceClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*20)
	defer cancel()

	res, err := c.Stop(ctx, &pb.Empty{})
	if err != nil {
		log.Printf("did not Stopped: %v %v", res, err)
		_, _ = c.Stop(ctx, &pb.Empty{})
		return false, err
	}

	return true, nil
}

func ExitTunnelService() (bool, error) {
	conn, err := grpc.Dial("127.0.0.1:18020", grpc.WithInsecure())
	if err != nil {
		log.Printf("did not connect: %v", err)
		return false, err
	}
	defer conn.Close()
	c := pb.NewTunnelServiceClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*1)
	defer cancel()

	res, err := c.Exit(ctx, &pb.Empty{})
	if res != nil {
		log.Printf("did not exit: %v %v", res, err)
		return false, err
	}

	return true, nil
}

func readTailLog(path string, maxBytes int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Sprintf("<unreadable: %v>", err)
	}
	s := strings.TrimSpace(string(data))
	if len(s) > maxBytes {
		s = "..." + s[len(s)-maxBytes:]
	}
	if s == "" {
		return "<empty>"
	}
	return s
}

func runTunnelService(opt HiddifyOptions) (bool, error) {
	executablePath := getTunnelServicePath()
	fmt.Printf("Executable path is %s\n", executablePath)
	out, installErr := ExecuteCmd(executablePath, false, "tunnel", "install")
	fmt.Println("Shell command executed:", out, installErr)
	if installErr == nil {
		for i := 0; i < 24; i++ {
			if isPortInUse("18020") {
				break
			}
			<-time.After(250 * time.Millisecond)
		}
	}
	var runErr error
	if !isPortInUse("18020") {
		out, runErr = ExecuteCmd(executablePath, true, "tunnel", "run")
		fmt.Println("Shell command executed without flag:", out, runErr)
		if runErr == nil {
			for i := 0; i < 20; i++ {
				if isPortInUse("18020") {
					break
				}
				<-time.After(250 * time.Millisecond)
			}
		}
	}
	ok, err := startTunnelRequest(opt, false)
	if err != nil {
		return ok, fmt.Errorf(
			"%w | cli=%s | installErr=%v | runErr=%v | installLog=%s | runLog=%s",
			err,
			executablePath,
			installErr,
			runErr,
			readTailLog("/tmp/hiddify-tunnel-install.log", 300),
			readTailLog("/tmp/hiddify-tunnel.log", 300),
		)
	}
	return ok, nil
}

func getTunnelServicePath() string {
	exePath, _ := os.Executable()
	binFolder := filepath.Dir(exePath)
	var fullPath string
	switch runtime.GOOS {
	case "windows":
		fullPath = filepath.Join(binFolder, "HiddifyCli.exe")
	case "darwin":
		candidates := []string{
			filepath.Join(binFolder, "HiddifyCli"),
			filepath.Join(binFolder, "..", "Frameworks", "HiddifyCli"),
		}
		for _, candidate := range candidates {
			if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
				fullPath = candidate
				break
			}
		}
		if fullPath == "" {
			log.Printf("WARNING: HiddifyCli not found in %v, falling back to %s", candidates, exePath)
			fullPath = exePath
		}
	default:
		cli := filepath.Join(binFolder, "HiddifyCli")
		if _, err := os.Stat(cli); err == nil {
			fullPath = cli
		} else {
			fullPath = exePath
		}
	}

	abspath, _ := filepath.Abs(fullPath)
	return abspath
}
