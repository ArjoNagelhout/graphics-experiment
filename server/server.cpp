#include <iostream>

int main(int argc, char** argv)
{
    std::cout << "I'm a server" << std::endl;

    // the server will be responsible for managing collaborative design / review sessions
    // and importing files that are sent to the client.

    // server architecture
    // c++ might not be the right language to program the entire server in,
    // as handling authentication and web page requests might be better with
    // a higher level language.

    // many parts of the server will be akin to a webserver, i.e. serving requests over HTTP.
    //
    // the realtime part of the app would be over websockets / a different protocol that
    // requires speed. but HTTP requests might not need this.

    // front-end on the web would have to be in React / similar front-end framework
    // hosting? -> AWS / Google Cloud / Azure
    // Authentication -> auth0?
    // session management
    // we need to store user data securely -> databases, relational database (MySQL) or NoSQL e.g. DynamoDB
    // for the realtime part, have the server e.g. EC2 instances

    // infrastructure as code (IaC), e.g. Terraform.
    // managing AWS directly via the console is a pain in the butt.

    // set spending limits

    // containerization using Docker / Kubernetes

    // simultaneous editing of data -> e.g. Optimistic concurrency control, or whatever Figma or Google Docs use for
    // conflict resolution
}