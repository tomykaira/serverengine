#
# ServerEngine
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

module ServerEngine
  module SocketManagerWin

    require 'win32/pipe'
    require 'serverengine/winsock'

    module ClientModule
      private

      def connect_peer(path)
        return Win32::Pipe::Client.new(@pipe_name)
      end

      def recv_tcp(peer, proto)
        # TODO call rb_w32_wrap_io_handle with TCPServer so that clients can use TCPServer API
        return WinSock::WSASocketA(Socket::AF_INET, Socket::SOCK_STREAM, 0, proto, 0, WinSock::WSA_FLAG_OVERLAPPED)
      end

      def recv_udp(peer, proto)
        # TODO call rb_w32_wrap_io_handle with UDPSocket so that clients can use UDPSocket API
        return WinSock::WSASocketA(Socket::AF_INET, Socket::SOCK_DGRAM, 0, proto, 0, WinSock::WSA_FLAG_OVERLAPPED)
      end
    end

    class Server
      private

      def listen_tcp_new(bind, port)
        # TODO IPv6 is not supported

        sock = WinSock::WSASocketA(Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP, nil, 0, WinSock::WSA_FLAG_OVERLAPPED)
        # TODO call rb_w32_wrap_io_handle so that sock is closed by SocketManager::Server#close or GC

        sock_addr = pack_sockaddr(bind_ip, port)
        WinSock::bind(sock, listen_addr, listen_addr.size)
        WinSock::listen(sock, Socket::SOMAXCONN)

        return sock
      end

      def listen_udp_new(bind_ip, port)
        # TODO IPv6 is not supported

        sock = WinSock::WSASocketA(Socket::AF_INET, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP, nil, 0, WinSock::WSA_FLAG_OVERLAPPED)
        # TODO call rb_w32_wrap_io_handle so that sock is closed by SocketManager::Server#close or GC

        sock_addr = pack_sockaddr(bind_ip, port)
        WinSock::bind(sock, sock_addr, sock_addr.size)

        return sock
      end

      def pack_sockaddr(bind_ip, port)
        # implementing Socket.pack_sockaddr_in here
        sock_addr = WinSock::SockaddrIn.new
        in_addr = WinSock::InAddr.new
        in_addr[:s_addr] = bind_ip.to_i
        sock_addr[:sin_family] = Socket::AF_INET
        sock_addr[:sin_port] = htons(port)
        sock_addr[:sin_addr] = in_addr
        return sock_addr
      end

      def htons(h)
        [h].pack("S").unpack("n")[0]
      end

      def start_server(path)
        @running = true

        @thread = Thread.new do
          begin
            pipe = nil
            while @running
              pipe ||= Win32::Pipe::Server.new(path, Win32::Pipe::DEFAULT_PIPE_MODE, Win32::Pipe::DEFAULT_OPEN_MODE | Win32::Pipe::OVERLAPPED)
              pipe.wait(1)
              if pipe.connect
                Thread.new(pipe, &method(:process_peer))  # process_peer calls send_socket
                pipe = nil
              end
            end
          rescue => e
            ServerEngine.dump_uncaught_error(e)
          end
        end

        return path
      end

      def stop_server
        @running = false
        @thread.join
      end

      def send_socket(peer, pid, method, bind, port)
        case method
        when :listen_tcp
          sock = listen_tcp(bind, port)
          type = Socket::SOCK_STREAM
        when :listen_udp
          sock = listen_tcp(bind, port)
          type = Socket::SOCK_DGRAM
        else
          raise ArgumentError, "Unknown method: #{method.inspect}"
        end

        proto = WinSock::WSAPROTOCOL_INFO.new
        unless WinSock::WSADuplicateSocketA(sock, pid, proto) == 0
          raise "WSADuplicateSocketA faild (0x%x)" % WinSock::WSAGetLastError()
        end

        SocketManager.send_peer(peer, proto)
      end
    end

  end
end