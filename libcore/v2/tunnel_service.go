package v2

import (
	"context"
	"fmt"
	"log"
	"os"
	"runtime"

	pb "github.com/hiddify/hiddify-core/hiddifyrpc"
)

func (s *TunnelService) Start(ctx context.Context, in *pb.TunnelStartRequest) (*pb.TunnelResponse, error) {
	if in.ServerPort == 0 {
		in.ServerPort = 1080
	}
	useFlutterBridge = false
	res, err := Start(&pb.StartRequest{
		ConfigContent:          makeTunnelConfig(in.Ipv6, in.ServerPort, in.StrictRoute, in.EndpointIndependentNat, in.Stack),
		EnableOldCommandServer: false,
		DisableMemoryLimit:     true,
		EnableRawConfig:        true,
	})
	fmt.Printf("Start Result: %+v\n", res)
	if err != nil {
		return &pb.TunnelResponse{
			Message: err.Error(),
		}, err
	}
	return &pb.TunnelResponse{
		Message: "OK",
	}, err
}

func makeTunnelConfig(Ipv6 bool, ServerPort int32, StrictRoute bool, EndpointIndependentNat bool, Stack string) string {
	var ipv6 string
	if Ipv6 {
		ipv6 = `      "inet6_address": "fdfe:dcba:9876::1/126",`
	} else {
		ipv6 = ""
	}
	var interfaceName string
	if runtime.GOOS == "windows" {
		interfaceName = `"interface_name": "HiddifyTunnel",`
	} else {
		// on darwin (macOS) and linux, omit interface_name so the OS kernel
		// automatically allocates a valid tun/utun interface (e.g. utun3 on macOS).
		interfaceName = ""
	}

	base := `{
		"log":{
			"level": "warn"
		},
		"dns": {
		  "servers": [
			{
			  "tag": "dns-local",
			  "address": "udp://127.0.0.1:16450",
			  "detour": "direct-out"
			}
		  ]
		},
		"inbounds": [
		  {
			"type": "tun",
			"tag": "tun-in",
			` + interfaceName + `
			"inet4_address": "172.19.0.1/28",
			` + ipv6 + `
			"auto_route": true,
			"strict_route": ` + fmt.Sprintf("%t", StrictRoute) + `,
			"endpoint_independent_nat": ` + fmt.Sprintf("%t", EndpointIndependentNat) + `,
			"stack": "` + Stack + `",
			"sniff": true,
			"sniff_override_destination": true
		  }
		],
		"outbounds": [
		  {
			"type": "socks",
			"tag": "socks-out",
			"server": "127.0.0.1",
			"server_port": ` + fmt.Sprintf("%d", ServerPort) + `,
			"version": "5"
		  },
		  {
			"type": "dns",
			"tag": "dns-out"
		  },
		  {
			"type": "direct",
			"tag": "direct-out"
		  }
		],
		"route": {
		  "auto_detect_interface": true,
		  "rules": [
			{
			  "protocol": "dns",
			  "outbound": "dns-out"
			},
			{
			  "port": 53,
			  "outbound": "dns-out"
			},
			{
			  "ip_is_private": true,
			  "outbound": "direct-out"
			},
			{
			  "process_name": [
				"Hiddify.exe",
				"Hiddify",
				"HiddifyCli",
				"HiddifyCli.exe"
			  ],
			  "outbound": "direct-out"
			}
		  ]
		}
	  }`

	return base
}

func (s *TunnelService) Stop(ctx context.Context, _ *pb.Empty) (*pb.TunnelResponse, error) {
	res, err := Stop()
	log.Printf("Stop Result: %+v\n", res)
	if err != nil {
		return &pb.TunnelResponse{
			Message: err.Error(),
		}, err
	}

	return &pb.TunnelResponse{
		Message: "OK",
	}, err
}
func (s *TunnelService) Status(ctx context.Context, _ *pb.Empty) (*pb.TunnelResponse, error) {

	return &pb.TunnelResponse{
		Message: "Not Implemented",
	}, nil
}
func (s *TunnelService) Exit(ctx context.Context, _ *pb.Empty) (*pb.TunnelResponse, error) {
	Stop()
	os.Exit(0)
	return &pb.TunnelResponse{
		Message: "OK",
	}, nil
}
