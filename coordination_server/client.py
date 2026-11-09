#!/usr/bin/env python

"""Client using the asyncio API."""

import asyncio
import socket
from aioconsole import ainput
import json
import threading

SOURCE_ADDR = ""
SOURCE_PORT = 54325
DEST_ADDR = "34.173.254.68"
DEST_PORT = 8080

MODE = 0

def set_interval(seconds, func):
    state = {
        "timer": None,
        "cancelled": False,
        "lock": threading.Lock(),
    }

    def helper():
        with state["lock"]:
            if state["cancelled"]:
                return
        try:
            func()
        except Exception as e:
            print("Timer failed:", e)

        with state["lock"]:
            if state["cancelled"]:
                return

            state["timer"] = threading.Timer(seconds, helper)
            state["timer"].start()

    def cancel():
        with state["lock"]:
            state["cancelled"] = True
            if state["timer"] is not None:
                state["timer"].cancel()

    state["timer"] = threading.Timer(seconds, helper)
    state["timer"].start()
    state["cancel"] = cancel

    return state

class ClientConnection():
    def __init__(self, source_addr = SOURCE_ADDR, source_port = SOURCE_PORT, dest_addr = DEST_ADDR, dest_port = DEST_PORT):
        self.socket: socket.socket
        self.interval: dict
        self.peer: dict
        self.mode = -1 # -1: None, 0: Coord, 1: P2P

        self.sourse_addr = source_addr
        self.sourse_port = source_port
        self.dest_addr = dest_addr
        self.dest_port = dest_port

    def listen_to_coordination_server(self):
        '''
        Listens to the coordination server for updates.
        Returns when coordination server has determined peer.
        '''
        if self.mode != 0:
            print("Trying to listen to coordination server when not connected to one.")
            return
        while(True):
            try:
                message = self.socket.recv(1024)
                if not message: break
                
                message = json.loads(message)
                print("RECEIVED:", message)
                if message.get("messageType") == 1:
                    print("CONNECTING")
                    return message
            except Exception as e:
                print(e)

    async def poll_for_p2p_connection(self):
        '''
        Polls the user for which peer he wants to connect to.
        Sends the preference to coordination server.
        
        Needs to be cancelled to end.
        '''
        if self.mode != 0:
            print("Trying to ping a coordination server when not connected to one.")
        while(True):
            try:
                # Non-blocking terminal prompt
                ip = await ainput(">>> Enter ip to connect to:")
                port = await ainput(">>> Enter port or N(no) to abort:")

                if(port[0].lower() == 'n'):
                    continue

                print("Sending")
                res = self.socket.sendall(json.dumps({
                    "messageType":2,
                    "peer": {
                        "ip": ip,
                        "port": int(port)
                    }
                }).encode())
                print("got back")
                print(res)
            except asyncio.CancelledError:
                break;
            except Exception as e:
                print(e)
    
    async def _handle_coord_connection(self):
        '''
        Helper function.

        Connects to the coordination server,
        starts polling the user for peer selection,
        and returns with the peer to connect to.

        '''
        if self.mode != 0:
            print("Trying to handle a coordination server when not connected to one.")
        
        # Minor bug: if server has responsded already we miss the update
        
        # Send port listening function to new thread since socket.recv is blocking
        listen_task = asyncio.to_thread(self.listen_to_coordination_server)

        # Does not need new thread since io is async
        poll_task = asyncio.create_task(self.poll_for_p2p_connection())

        message = await listen_task
        print("trying to stop polling")
        poll_task.cancel()
        await poll_task
        print("stopped polling")
        return message


    def listen_p2p(self):
        '''
        Listens for messages from peer.
        '''
        if self.mode != 1:
            print("Trying to ping a peer when not connected to one.")
        while(True):
            try:
                message = self.socket.recv(1024)
                if not message: break
                
                message = json.loads(message)

                if message['messageType'] == 0:
                    continue
                print("RECEIVED:", message)
            except Exception as e:
                print("Exception in p2p:", e)

    async def poll_p2p(self):
        '''
        Polls user for messages to send to peer.

        Needs to be cancelled to end.
        '''
        if self.mode != 1:
            print("Trying to send a message to a peer when not connected to one.")
        while True:
            try:
                # Non-blocking terminal prompt
                message = await ainput(">>> Enter message to send:")

                self.socket.sendall(json.dumps({
                    "messageType": 1,
                    "message":message
                }).encode())
            except Exception as e:
                print("Exception in p2p:", e)

    async def connect_to_server(self):
        '''
        Initialises a UDP connection with pings to coordination server.
        '''
        await self._connect(self.sourse_addr, self.sourse_port, self.dest_addr, self.dest_port, 0)

    async def connect_to_peer(self, peer):
        '''
        Initialises a UDP connection with pings to coordination server.
        '''
        await self._connect(self.sourse_addr, self.sourse_port, peer.get("peer").get("address"), peer.get("peer").get("port") , 1)
        self.peer = peer
    
    async def _connect(self, source_addr, source_port, remote_addr, remote_port, mode):
        '''
        Initialises a UDP connection with pings.
        '''

        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((source_addr, source_port))
        
        s.connect((remote_addr, remote_port))

        print("Sending hello")
        s.sendall(json.dumps({"messageType": 0}).encode())

        self.interval = set_interval(2, lambda:  s.sendall(json.dumps({"messageType": 0}).encode()))

        self.socket = s

        self.mode = mode

    async def disconnect(self):
        '''
        Disconnects and cleans up connection
        '''
        self.interval['cancel']()
        self.socket.close()
        self.mode = -1


        # if not t2.cancel():
        #     print("Could not cancel polling")

    async def _handle_peer_connection(self):
        '''
        Helper function.

        Sets up server/client config
        based on coordination server response.
        '''
        if self.mode != 1:
            print("Trying to handle a peer when not connected to one.")
        if self.peer.get("role") == 0:
            print("role is server")
            self.listen_p2p()
        else:
            print("role is client")
            await self.poll_p2p()
                
        
#     print("Cleaning up connect")


async def main():
    client = ClientConnection()

    # Connect to coordination server
    await client.connect_to_server()
    
    peer = await client._handle_coord_connection()

    await client.disconnect()

    await client.connect_to_peer(peer)

    await client._handle_peer_connection()


if __name__ == "__main__":
    asyncio.run(main())












    # Steps:
    # 1. Connect to coord
    # 2. Listen to coord
    # 3. Poll user
    # 4. clean up coord connection
    # 5. Set up role as server/client
    # 6. Listen/poll
