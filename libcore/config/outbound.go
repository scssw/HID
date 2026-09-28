package config

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net"
	"strconv"
	"strings"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

type outboundMap map[string]interface{}

func patchOutboundMux(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if configOpt.Mux.Enable {
		multiplex := option.OutboundMultiplexOptions{
			Enabled:    true,
			Padding:    configOpt.Mux.Padding,
			MaxStreams: configOpt.Mux.MaxStreams,
			Protocol:   configOpt.Mux.Protocol,
		}
		obj["multiplex"] = multiplex
		// } else {
		// 	delete(obj, "multiplex")
	}
	return obj
}

func patchOutboundTLSTricks(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if base.Type == C.TypeSelector || base.Type == C.TypeURLTest || base.Type == C.TypeBlock || base.Type == C.TypeDNS {
		return obj
	}
	if isOutboundReality(base) {
		return obj
	}

	var tls *option.OutboundTLSOptions
	var transport *option.V2RayTransportOptions
	if base.VLESSOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.VLESSOptions.OutboundTLSOptionsContainer.TLS
		transport = base.VLESSOptions.Transport
	} else if base.TrojanOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.TrojanOptions.OutboundTLSOptionsContainer.TLS
		transport = base.TrojanOptions.Transport
	} else if base.VMessOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.VMessOptions.OutboundTLSOptionsContainer.TLS
		transport = base.VMessOptions.Transport
	}
	if base.Type == C.TypeXray {
		if configOpt.TLSTricks.EnableFragment {
			if obj["xray_fragment"] == nil || obj["xray_fragment"].(map[string]any)["packets"] == "" {
				obj["xray_fragment"] = map[string]any{
					"packets":  "tlshello",
					"length":   configOpt.TLSTricks.FragmentSize,
					"interval": configOpt.TLSTricks.FragmentSleep,
				}
			}
		}
	}
	if base.Type == C.TypeDirect {
		return patchOutboundFragment(base, configOpt, obj)
	}

	if tls == nil || !tls.Enabled || transport == nil {
		return obj
	}

	if transport.Type != C.V2RayTransportTypeWebsocket && transport.Type != C.V2RayTransportTypeGRPC && transport.Type != C.V2RayTransportTypeHTTPUpgrade {
		return obj
	}

	if outtls, ok := obj["tls"].(map[string]interface{}); ok {
		obj = patchOutboundFragment(base, configOpt, obj)
		tlsTricks := tls.TLSTricks
		if tlsTricks == nil {
			tlsTricks = &option.TLSTricksOptions{}
		}
		tlsTricks.MixedCaseSNI = tlsTricks.MixedCaseSNI || configOpt.TLSTricks.MixedSNICase

		if configOpt.TLSTricks.EnablePadding {
			tlsTricks.PaddingMode = "random"
			tlsTricks.PaddingSize = configOpt.TLSTricks.PaddingSize
			// fmt.Printf("--------------------%+v----%+v", tlsTricks.PaddingSize, configOpt)
			outtls["utls"] = map[string]interface{}{
				"enabled":     true,
				"fingerprint": "custom",
			}
		}

		outtls["tls_tricks"] = tlsTricks
		// if tlsTricks.MixedCaseSNI || tlsTricks.PaddingMode != "" {
		// 	// } else {
		// 	// 	tls["tls_tricks"] = nil
		// }
		// fmt.Printf("-------%+v------------- ", tlsTricks)
	}
	return obj
}

func patchOutboundFragment(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if configOpt.TLSTricks.EnableFragment {
		obj["tcp_fast_open"] = false
		obj["tls_fragment"] = option.TLSFragmentOptions{
			Enabled: configOpt.TLSTricks.EnableFragment,
			Size:    configOpt.TLSTricks.FragmentSize,
			Sleep:   configOpt.TLSTricks.FragmentSleep,
		}

	}

	return obj
}

func isOutboundReality(base option.Outbound) bool {
	// this function checks reality status ONLY FOR VLESS.
	// Some other protocols can also use reality, but it's discouraged as stated in the reality document
	if base.Type != C.TypeVLESS {
		return false
	}
	if base.VLESSOptions.OutboundTLSOptionsContainer.TLS == nil {
		return false
	}
	if base.VLESSOptions.OutboundTLSOptionsContainer.TLS.Reality == nil {
		return false
	}
	return base.VLESSOptions.OutboundTLSOptionsContainer.TLS.Reality.Enabled
}

func patchOutbound(base option.Outbound, configOpt HiddifyOptions, staticIpsDns map[string][]string) (*option.Outbound, string, error) {
	formatErr := func(err error) error {
		return fmt.Errorf("error patching outbound[%s][%s]: %w", base.Tag, base.Type, err)
	}
	err := patchWarp(&base, &configOpt, true, staticIpsDns)
	if err != nil {
		return nil, "", formatErr(err)
	}
	var outbound option.Outbound

	jsonData, err := base.MarshalJSON()
	if err != nil {
		return nil, "", formatErr(err)
	}

	var obj outboundMap
	err = json.Unmarshal(jsonData, &obj)
	if err != nil {
		return nil, "", formatErr(err)
	}
	var serverDomain string
	if detour, ok := obj["detour"].(string); !ok || detour == "" {
		if server, ok := obj["server"].(string); ok {
			if server != "" && net.ParseIP(server) == nil {
				serverDomain = fmt.Sprintf("full:%s", server)
			}
		}
	}

	obj = patchOutboundTLSTricks(base, configOpt, obj)

	switch base.Type {
	case C.TypeVMess, C.TypeVLESS, C.TypeTrojan, C.TypeShadowsocks:
		obj = patchOutboundMux(base, configOpt, obj)
	case C.TypeHysteria2, C.TypeHysteria:
		obj = patchHysteriaPortHopping(base, obj)
	}

	modifiedJson, err := json.Marshal(obj)
	if err != nil {
		return nil, "", formatErr(err)
	}

	err = outbound.UnmarshalJSON(modifiedJson)
	if err != nil {
		return nil, "", formatErr(err)
	}

	return &outbound, serverDomain, nil
}

// ParsePortRanges parses strings like "20000-50000", "20000:50000, 4433" or ["20000-50000"]
func ParsePortRanges(mport string) [][2]uint16 {
	var ranges [][2]uint16
	for _, part := range strings.Split(mport, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		sep := ""
		if strings.Contains(part, "-") {
			sep = "-"
		} else if strings.Contains(part, ":") {
			sep = ":"
		}
		if sep != "" {
			sub := strings.SplitN(part, sep, 2)
			start, err1 := strconv.ParseUint(strings.TrimSpace(sub[0]), 10, 16)
			end, err2 := strconv.ParseUint(strings.TrimSpace(sub[1]), 10, 16)
			if err1 == nil && err2 == nil && start > 0 && end > 0 {
				if start > end {
					start, end = end, start
				}
				ranges = append(ranges, [2]uint16{uint16(start), uint16(end)})
			}
		} else {
			p, err := strconv.ParseUint(part, 10, 16)
			if err == nil && p > 0 {
				ranges = append(ranges, [2]uint16{uint16(p), uint16(p)})
			}
		}
	}
	return ranges
}

func PickRandomPortFromMport(mport string) uint16 {
	ranges := ParsePortRanges(mport)
	if len(ranges) == 0 {
		return 0
	}
	var total int
	for _, r := range ranges {
		total += int(r[1] - r[0] + 1)
	}
	if total <= 0 {
		return 0
	}
	idx := rand.Intn(total)
	for _, r := range ranges {
		count := int(r[1] - r[0] + 1)
		if idx < count {
			return r[0] + uint16(idx)
		}
		idx -= count
	}
	return ranges[0][0]
}

func patchHysteriaPortHopping(base option.Outbound, obj outboundMap) outboundMap {
	mportStr := ""
	if base.Type == C.TypeHysteria2 {
		mportStr = base.Hysteria2Options.Mport
		if mportStr == "" && len(base.Hysteria2Options.ServerPorts) > 0 {
			mportStr = strings.Join(base.Hysteria2Options.ServerPorts, ",")
		}
	} else if base.Type == C.TypeHysteria {
		mportStr = base.HysteriaOptions.Mport
		if mportStr == "" && len(base.HysteriaOptions.ServerPorts) > 0 {
			mportStr = strings.Join(base.HysteriaOptions.ServerPorts, ",")
		}
	}
	if mportStr == "" {
		if v, ok := obj["mport"].(string); ok {
			mportStr = v
		} else if sp, ok := obj["server_ports"].([]interface{}); ok && len(sp) > 0 {
			var spList []string
			for _, item := range sp {
				if s, ok := item.(string); ok {
					spList = append(spList, s)
				}
			}
			mportStr = strings.Join(spList, ",")
		}
	}
	if mportStr != "" {
		if pickedPort := PickRandomPortFromMport(mportStr); pickedPort > 0 {
			fmt.Printf("[Port Hopping] Outbound [%s] selected random port %d from range %s\n", base.Tag, pickedPort, mportStr)
			obj["server_port"] = pickedPort
		}
	}
	return obj
}


// func (o outboundMap) transportType() string {
// 	if transport, ok := o["transport"].(map[string]interface{}); ok {
// 		if transportType, ok := transport["type"].(string); ok {
// 			return transportType
// 		}
// 	}
// 	return ""
// }
