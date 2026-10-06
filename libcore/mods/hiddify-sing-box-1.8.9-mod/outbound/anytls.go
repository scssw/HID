package outbound

import (
	"context"
	"net"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/dialer"
	"github.com/sagernet/sing-box/common/tls"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/transport/anytls"
	"github.com/sagernet/sing/common"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/common/uot"
)

var _ adapter.Outbound = (*AnyTLS)(nil)

type AnyTLS struct {
	myOutboundAdapter
	dialer     N.Dialer
	serverAddr M.Socksaddr
	tlsConfig  tls.Config
	client     *anytls.Client
	uotClient  *uot.Client
}

func NewAnyTLS(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options option.AnyTLSOutboundOptions) (*AnyTLS, error) {
	outboundDialer, err := dialer.New(router, options.DialerOptions)
	if err != nil {
		return nil, err
	}
	outbound := &AnyTLS{
		myOutboundAdapter: myOutboundAdapter{
			protocol:     C.TypeAnyTLS,
			network:      options.Network.Build(),
			router:       router,
			logger:       logger,
			tag:          tag,
			dependencies: withDialerDependency(options.DialerOptions),
		},
		dialer:     outboundDialer,
		serverAddr: options.ServerOptions.Build(),
	}

	if options.TLS != nil {
		outbound.tlsConfig, err = tls.NewClient(ctx, options.Server, common.PtrValueOrDefault(options.TLS))
		if err != nil {
			return nil, err
		}
	} else {
		outbound.tlsConfig, err = tls.NewClient(ctx, options.Server, option.OutboundTLSOptions{
			Enabled:    true,
			ServerName: options.Server,
		})
		if err != nil {
			return nil, err
		}
	}

	anytlsConfig := anytls.ClientConfig{
		Password:                 options.Password,
		IdleSessionCheckInterval: time.Duration(options.IdleSessionCheckInterval),
		IdleSessionTimeout:       time.Duration(options.IdleSessionTimeout),
		MinIdleSession:           options.MinIdleSession,
		Logger:                   logger,
		DialOut: func(ctx context.Context) (net.Conn, error) {
			conn, err := outbound.dialer.DialContext(ctx, N.NetworkTCP, outbound.serverAddr)
			if err != nil {
				return nil, err
			}
			if outbound.tlsConfig != nil {
				conn, err = tls.ClientHandshake(ctx, conn, outbound.tlsConfig)
				if err != nil {
					conn.Close()
					return nil, err
				}
			}
			return conn, nil
		},
	}

	outbound.client, err = anytls.NewClient(ctx, anytlsConfig)
	if err != nil {
		return nil, err
	}

	outbound.uotClient = &uot.Client{
		Dialer:  (*anytlsDialer)(outbound),
		Version: uot.Version,
	}

	return outbound, nil
}

func (h *AnyTLS) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	ctx, metadata := adapter.AppendContext(ctx)
	metadata.Outbound = h.tag
	metadata.Destination = destination
	switch N.NetworkName(network) {
	case N.NetworkTCP:
		h.logger.InfoContext(ctx, "outbound connection to ", destination)
		return h.client.CreateProxy(ctx, destination)
	case N.NetworkUDP:
		h.logger.InfoContext(ctx, "outbound UoT connect packet connection to ", destination)
		return h.uotClient.DialContext(ctx, network, destination)
	default:
		return nil, E.Extend(N.ErrUnknownNetwork, network)
	}
}

func (h *AnyTLS) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	ctx, metadata := adapter.AppendContext(ctx)
	metadata.Outbound = h.tag
	metadata.Destination = destination
	h.logger.InfoContext(ctx, "outbound UoT packet connection to ", destination)
	return h.uotClient.ListenPacket(ctx, destination)
}

func (h *AnyTLS) NewConnection(ctx context.Context, conn net.Conn, metadata adapter.InboundContext) error {
	return NewConnection(ctx, h, conn, metadata)
}

func (h *AnyTLS) NewPacketConnection(ctx context.Context, conn N.PacketConn, metadata adapter.InboundContext) error {
	return NewPacketConnection(ctx, h, conn, metadata)
}

func (h *AnyTLS) InterfaceUpdated() {
}

func (h *AnyTLS) Close() error {
	if h.client != nil {
		return h.client.Close()
	}
	return nil
}

type anytlsDialer AnyTLS

func (h *anytlsDialer) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	return h.client.CreateProxy(ctx, destination)
}

func (h *anytlsDialer) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return nil, E.New("packet connection not supported directly by anytls")
}
