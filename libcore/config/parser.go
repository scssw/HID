package config

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/hiddify/ray2sing/ray2sing"
	"github.com/sagernet/sing-box/experimental/libbox"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/batch"
	SJ "github.com/sagernet/sing/common/json"
	"github.com/xmdhs/clash2singbox/convert"
	"github.com/xmdhs/clash2singbox/model/clash"
	"gopkg.in/yaml.v3"
)

//go:embed config.json.template
var configByte []byte

type hy2Hint struct {
	upMbps       *int
	downMbps     *int
	obfsPassword string
}

func ParseConfig(path string, debug bool) ([]byte, error) {
	content, err := os.ReadFile(path)
	os.Chdir(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	return ParseConfigContent(string(content), debug, nil, false)
}

func ParseConfigContentToOptions(contentstr string, debug bool, configOpt *HiddifyOptions, fullConfig bool) (*option.Options, error) {
	content, err := ParseConfigContent(contentstr, debug, configOpt, fullConfig)
	if err != nil {
		return nil, err
	}
	var options option.Options
	err = json.Unmarshal(content, &options)
	if err != nil {
		return nil, err
	}
	return &options, nil
}

func ParseConfigContent(contentstr string, debug bool, configOpt *HiddifyOptions, fullConfig bool) ([]byte, error) {
	if configOpt == nil {
		configOpt = DefaultHiddifyOptions()
	}
	contentstr = normalizeNaiveLinks(contentstr)
	content := []byte(contentstr)
	var jsonObj map[string]interface{} = make(map[string]interface{})

	fmt.Printf("Convert using json\n")
	var tmpJsonResult any
	jsonDecoder := json.NewDecoder(SJ.NewCommentFilter(bytes.NewReader(content)))
	if err := jsonDecoder.Decode(&tmpJsonResult); err == nil {
		if tmpJsonObj, ok := tmpJsonResult.(map[string]interface{}); ok {
			if tmpJsonObj["outbounds"] == nil {
				jsonObj["outbounds"] = []interface{}{jsonObj}
			} else {
				if fullConfig || (configOpt != nil && configOpt.EnableFullConfig) {
					jsonObj = tmpJsonObj
				} else {
					jsonObj["outbounds"] = tmpJsonObj["outbounds"]
				}
			}
		} else if jsonArray, ok := tmpJsonResult.([]map[string]interface{}); ok {
			jsonObj["outbounds"] = jsonArray
		} else {
			return nil, fmt.Errorf("[SingboxParser] Incorrect Json Format")
		}

		normalizeNaiveOutboundsInJSON(jsonObj)

		newContent, _ := json.MarshalIndent(jsonObj, "", "  ")

		return patchConfig(newContent, "SingboxParser", configOpt)
	}

	v2rayStr, err := ray2sing.Ray2Singbox(string(content), configOpt.UseXrayCoreWhenPossible)
	if err == nil {
		upMbps, downMbps := extractHysteria2SpeedFromRawInput(string(content))
		if upMbps != nil || downMbps != nil {
			if patched, patchErr := patchHysteria2SpeedInSingboxJSON([]byte(v2rayStr), upMbps, downMbps); patchErr == nil {
				v2rayStr = string(patched)
			}
		}
		return patchConfig([]byte(v2rayStr), "V2rayParser", configOpt)
	}
	fmt.Printf("Convert using clash\n")
	clashObj := clash.Clash{}
	if err := yaml.Unmarshal(content, &clashObj); err == nil && clashObj.Proxies != nil {
		if len(clashObj.Proxies) == 0 {
			return nil, fmt.Errorf("[ClashParser] no outbounds found")
		}
		converted, err := convert.Clash2sing(clashObj)
		if err != nil {
			return nil, fmt.Errorf("[ClashParser] converting clash to sing-box error: %w", err)
		}
		output := configByte
		output, err = convert.Patch(output, converted, "", "", nil)
		if err != nil {
			return nil, fmt.Errorf("[ClashParser] patching clash config error: %w", err)
		}
		if hints := extractClashHy2Hints(content); len(hints) > 0 {
			if patched, patchErr := patchHysteria2HintsInSingboxJSON(output, hints); patchErr == nil {
				output = patched
			}
		}
		return patchConfig(output, "ClashParser", configOpt)
	}

	return nil, fmt.Errorf("unable to determine config format")
}

func extractHysteria2SpeedFromRawInput(raw string) (*int, *int) {
	lines := strings.FieldsFunc(raw, func(r rune) bool {
		return r == '\r' || r == '\n'
	})
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if !strings.HasPrefix(strings.ToLower(line), "hysteria2://") {
			continue
		}
		u, err := url.Parse(line)
		if err != nil {
			continue
		}
		q := u.Query()
		up := parseMbpsIntString(firstNonEmpty(q.Get("upmbps"), q.Get("up")))
		down := parseMbpsIntString(firstNonEmpty(q.Get("downmbps"), q.Get("down")))
		if up == nil && down != nil {
			defaultUp := 20
			up = &defaultUp
		}
		if up != nil || down != nil {
			return up, down
		}
	}
	return nil, nil
}

func patchHysteria2SpeedInSingboxJSON(content []byte, upMbps, downMbps *int) ([]byte, error) {
	if upMbps == nil && downMbps == nil {
		return content, nil
	}
	var options option.Options
	if err := json.Unmarshal(content, &options); err != nil {
		return content, err
	}
	changed := false
	for i := range options.Outbounds {
		if options.Outbounds[i].Type != "hysteria2" {
			continue
		}
		if upMbps != nil && options.Outbounds[i].Hysteria2Options.UpMbps == 0 {
			options.Outbounds[i].Hysteria2Options.UpMbps = *upMbps
			changed = true
		}
		if downMbps != nil && options.Outbounds[i].Hysteria2Options.DownMbps == 0 {
			options.Outbounds[i].Hysteria2Options.DownMbps = *downMbps
			changed = true
		}
	}
	if !changed {
		return content, nil
	}
	return json.MarshalIndent(options, "", "  ")
}

func patchHysteria2HintsInSingboxJSON(content []byte, hints map[string]hy2Hint) ([]byte, error) {
	var options option.Options
	if err := json.Unmarshal(content, &options); err != nil {
		return content, err
	}
	changed := false
	for i := range options.Outbounds {
		out := &options.Outbounds[i]
		if out.Type != "hysteria2" {
			continue
		}
		hint, ok := hints[out.Tag]
		if !ok {
			continue
		}
		if hint.upMbps != nil && out.Hysteria2Options.UpMbps == 0 {
			out.Hysteria2Options.UpMbps = *hint.upMbps
			changed = true
		}
		if hint.downMbps != nil && out.Hysteria2Options.DownMbps == 0 {
			out.Hysteria2Options.DownMbps = *hint.downMbps
			changed = true
		}
		if hint.obfsPassword != "" {
			if out.Hysteria2Options.Obfs == nil {
				out.Hysteria2Options.Obfs = &option.Hysteria2Obfs{
					Type:     "salamander",
					Password: hint.obfsPassword,
				}
				changed = true
			} else {
				if out.Hysteria2Options.Obfs.Type == "" {
					out.Hysteria2Options.Obfs.Type = "salamander"
					changed = true
				}
				if out.Hysteria2Options.Obfs.Password == "" {
					out.Hysteria2Options.Obfs.Password = hint.obfsPassword
					changed = true
				}
			}
		}
	}
	if !changed {
		return content, nil
	}
	return json.MarshalIndent(options, "", "  ")
}

func extractClashHy2Hints(content []byte) map[string]hy2Hint {
	result := map[string]hy2Hint{}
	var root map[string]any
	if err := yaml.Unmarshal(content, &root); err != nil {
		return result
	}
	proxiesAny, ok := root["proxies"]
	if !ok {
		return result
	}
	proxies, ok := proxiesAny.([]any)
	if !ok {
		return result
	}
	for _, item := range proxies {
		pm, ok := item.(map[string]any)
		if !ok {
			continue
		}
		typ := strings.ToLower(strings.TrimSpace(toString(pm["type"])))
		if typ != "hysteria2" && typ != "hy2" {
			continue
		}
		tag := strings.TrimSpace(toString(pm["name"]))
		if tag == "" {
			continue
		}
		hint := hy2Hint{
			upMbps:       parseMbpsIntString(firstNonEmpty(toString(pm["up_mbps"]), toString(pm["upmbps"]), toString(pm["up"]))),
			downMbps:     parseMbpsIntString(firstNonEmpty(toString(pm["down_mbps"]), toString(pm["downmbps"]), toString(pm["down"]))),
			obfsPassword: strings.TrimSpace(toString(pm["obfs"])),
		}
		if hint.obfsPassword == "" {
			hint.obfsPassword = strings.TrimSpace(toString(pm["obfs-password"]))
		}
		result[tag] = hint
	}
	return result
}

func parseMbpsIntString(s string) *int {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return nil
	}
	start := -1
	end := -1
	dotSeen := false
	for i, r := range s {
		if r >= '0' && r <= '9' {
			if start == -1 {
				start = i
			}
			end = i + 1
			continue
		}
		if r == '.' && start != -1 && !dotSeen {
			dotSeen = true
			end = i + 1
			continue
		}
		if start != -1 {
			break
		}
	}
	if start == -1 || end <= start {
		return nil
	}
	f, err := strconv.ParseFloat(s[start:end], 64)
	if err != nil {
		return nil
	}
	val := int(f)
	return &val
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func toString(v any) string {
	switch vv := v.(type) {
	case string:
		return vv
	case int:
		return strconv.Itoa(vv)
	case int64:
		return strconv.FormatInt(vv, 10)
	case float64:
		return strconv.FormatFloat(vv, 'f', -1, 64)
	default:
		return ""
	}
}

func patchConfig(content []byte, name string, configOpt *HiddifyOptions) ([]byte, error) {
	options := option.Options{}
	err := json.Unmarshal(content, &options)
	if err != nil {
		return nil, fmt.Errorf("[SingboxParser] unmarshal error: %w", err)
	}
	b, _ := batch.New(context.Background(), batch.WithConcurrencyNum[*option.Outbound](2))
	for _, base := range options.Outbounds {
		out := base
		b.Go(base.Tag, func() (*option.Outbound, error) {
			err := patchWarp(&out, configOpt, false, nil)
			if err != nil {
				return nil, fmt.Errorf("[Warp] patch warp error: %w", err)
			}
			// options.Outbounds[i] = base
			return &out, nil
		})
	}
	if res, err := b.WaitAndGetResult(); err != nil {
		return nil, err
	} else {
		for i, base := range options.Outbounds {
			options.Outbounds[i] = *res[base.Tag].Value
		}
	}

	content, _ = json.MarshalIndent(options, "", "  ")

	fmt.Printf("%s\n", content)
	return validateResult(content, name)
}

func validateResult(content []byte, name string) ([]byte, error) {
	err := libbox.CheckConfig(string(content))
	if err != nil {
		return nil, fmt.Errorf("[%s] invalid sing-box config: %w", name, err)
	}
	return content, nil
}

func normalizeNaiveLinks(raw string) string {
	decoded, ok := decodeBase64Flexible(raw)
	target := raw
	if ok {
		target = decoded
	}

	lines := strings.Split(target, "\n")
	changed := false
	for i, line := range lines {
		trimmed := strings.TrimRight(line, "\r")
		clean := strings.TrimSpace(trimmed)
		if clean == "" || strings.HasPrefix(clean, "#") || strings.HasPrefix(clean, "//") {
			continue
		}
		lower := strings.ToLower(clean)
		if strings.HasPrefix(lower, "naive+https://") {
			lines[i] = "phttps://" + clean[len("naive+https://"):]
			changed = true
		} else if strings.HasPrefix(lower, "naive+http://") {
			lines[i] = "phttp://" + clean[len("naive+http://"):]
			changed = true
		} else if strings.HasPrefix(lower, "naive+quic://") {
			lines[i] = "phttps://" + clean[len("naive+quic://"):]
			changed = true
		} else if strings.HasPrefix(lower, "naive://") {
			lines[i] = "phttps://" + clean[len("naive://"):]
			changed = true
		}
	}

	if changed {
		return strings.Join(lines, "\n")
	}
	return raw
}

func decodeBase64Flexible(s string) (string, bool) {
	trimmed := strings.TrimSpace(s)
	if len(trimmed) < 8 {
		return s, false
	}
	if b, err := base64.StdEncoding.DecodeString(trimmed); err == nil && len(b) > 0 {
		return string(b), true
	}
	if b, err := base64.RawStdEncoding.DecodeString(trimmed); err == nil && len(b) > 0 {
		return string(b), true
	}
	if b, err := base64.URLEncoding.DecodeString(trimmed); err == nil && len(b) > 0 {
		return string(b), true
	}
	if b, err := base64.RawURLEncoding.DecodeString(trimmed); err == nil && len(b) > 0 {
		return string(b), true
	}
	return s, false
}

func normalizeNaiveOutboundsInJSON(obj map[string]interface{}) {
	outbounds, ok := obj["outbounds"].([]interface{})
	if !ok {
		if rawList, ok2 := obj["outbounds"].([]map[string]interface{}); ok2 {
			for _, m := range rawList {
				fixNaiveOutboundMap(m)
			}
		}
		return
	}
	for _, item := range outbounds {
		if m, ok := item.(map[string]interface{}); ok {
			fixNaiveOutboundMap(m)
		}
	}
}

func fixNaiveOutboundMap(m map[string]interface{}) {
	if typ, ok := m["type"].(string); ok && strings.ToLower(typ) == "naive" {
		m["type"] = "http"
		tlsVal, hasTLS := m["tls"]
		if !hasTLS || tlsVal == nil {
			m["tls"] = map[string]interface{}{
				"enabled": true,
			}
		} else if tlsMap, ok := tlsVal.(map[string]interface{}); ok {
			tlsMap["enabled"] = true
		}
	}
}

