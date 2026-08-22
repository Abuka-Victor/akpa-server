package internal

import (
	"fmt"
	"net"
)

func RunTCPServer() {
	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		fmt.Println("Error starting TCP socket server:", err)
		return
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			fmt.Println("Error accepting connection:", err)
			continue
		}
		fmt.Println("Somebody connected!")

		connId := AppRegistry.AddTunnel(conn)
		fmt.Println("The connection ID is:", connId)

		// conn.Write([]byte("Your link is live at https://akpa.victorabuka.com/" + connId + "\n"))
		conn.Write([]byte("Your link is live at https://localhost:8081/" + connId + "\n"))
		fmt.Println("Sent url link for", connId)

	}
}
