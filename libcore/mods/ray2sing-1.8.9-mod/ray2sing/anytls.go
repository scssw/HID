package ray2sing

import (
	C "github.com/sagernet/sing-box/constant"
	T "github.com/sagernet/sing-box/option"
)

func AnytlsSingbox(anytlsURL string) (*T.Outbound, error) {
	u, err := ParseUrl(anytlsURL, 443)
	if err != nil {
		return nil, err
	}
	decoded := u.Params

	password := u.Password
	if password == "" {
		password = u.Username
	}

	tlsOptions := getTLSOptions(decoded)
	if tlsOptions.TLS == nil {
		tlsOptions.TLS = &T.OutboundTLSOptions{
			Enabled:    true,
			ServerName: u.Hostname,
		}
	} else if tlsOptions.TLS.ServerName == "" {
		tlsOptions.TLS.ServerName = u.Hostname
	}

	opts := T.AnyTLSOutboundOptions{
		DialerOptions:               getDialerOptions(decoded),
		ServerOptions:               u.GetServerOption(),
		Password:                    password,
		OutboundTLSOptionsContainer: tlsOptions,
	}

	if interval := firstNonEmptyStr(decoded["idlesessioncheckinterval"], decoded["checkinterval"], decoded["idle_session_check_interval"]); interval != "" {
		if dur, err := T.ParseDuration(interval); err == nil {
			opts.IdleSessionCheckInterval = dur
		}
	}
	if timeout := firstNonEmptyStr(decoded["idlesessiontimeout"], decoded["timeout"], decoded["idle_session_timeout"]); timeout != "" {
		if dur, err := T.ParseDuration(timeout); err == nil {
			opts.IdleSessionTimeout = dur
		}
	}
	if minIdle := firstNonEmptyStr(decoded["minidlesession"], decoded["min_idle_session"]); minIdle != "" {
		opts.MinIdleSession = toInt(minIdle)
	}
	if meta := firstNonEmptyStr(decoded["clientmetadata"], decoded["client_metadata"]); meta != "" {
		opts.ClientMetadata = meta
	}

	tag := u.Name
	if tag == "" {
		tag = "anytls"
	}

	return &T.Outbound{
		Tag:           tag,
		Type:          C.TypeAnyTLS,
		AnyTLSOptions: opts,
	}, nil
}

func firstNonEmptyStr(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
