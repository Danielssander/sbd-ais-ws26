# Exercise 1 - Solution

## Run the program

From the repository root:

```sh
cd Exc_1/solution
go run .
```

Output:

```text
Hello, world!
Name: Daniel Sander Gassner
Course: Software Architectures for Big Data
```

The module requires Go 1.22 or newer and has no external dependencies.

## Validation

Checked with Go 1.27.2 on Windows:

- Formatted with `gofmt`.
- `go vet .` passed.
- `go run .` produced the output above.
- `go build` succeeded and the compiled program produced the same output.

The installed swaggo module is v1.16.6; its CLI reports v1.16.4.

## How it works

`Student` is a struct with two string fields, `Name` and `Course`. In `main`,
a struct literal creates a student with values for both fields.

`func (s Student) Print()` declares a method with a receiver of type `Student`.
Calling `student.Print()` prints the greeting and every field of that struct.
The receiver is passed by value, so the method works with a copy. A pointer
receiver is unnecessary here because the method only reads the fields.

## Go Tour study notes

The assigned reading is [A Tour of Go](https://go.dev/tour/basics/1), through
[methods and interfaces, page 20](https://go.dev/tour/methods/20).

- Basics: packages, imports, exported names, functions, variables, and types.
- Flow control: `for`, `if`, `switch`, and `defer`.
- More types: pointers, structs, arrays, slices, maps, and function values.
- Methods: a receiver attaches a method to a type. A value receiver gets a
  copy; a pointer receiver can modify the original value.
- Interfaces: a type implements an interface implicitly by providing its
  methods. Type assertions and type switches inspect interface values.
- `String() string` controls a type's text representation through
  `fmt.Stringer`; `Error() string` implements the `error` interface.

## Part 1 - Development environment

GitHub is set up and this repository is a fork of `ddibiasi/sbd-ais-ws26`.
Visual Studio Code is installed on the Windows machine.

Go and swaggo were installed in a local workspace tool directory for
validation. This is a portable setup; it does not add them to the system PATH.
For a regular development installation, install Go from
[go.dev](https://go.dev/dl/), then install the swaggo CLI:

```sh
go install github.com/swaggo/swag/cmd/swag@v1.16.6
```

Add Go's `bin` directory and `$(go env GOPATH)/bin` to PATH, then check:

```sh
go version
swag --version
```

Swaggo is a setup requirement for later API work. This hello world program
does not need generated Swagger documentation.

### Docker setup still to complete

Docker Engine and an Ubuntu VM are not installed on the Windows machine.
The Docker check has therefore **not** been run.

1. Set up an Ubuntu VM using the
   [Ubuntu VirtualBox guide](https://ubuntu.com/tutorials/how-to-run-ubuntu-desktop-on-a-virtual-machine-using-virtualbox#1-overview).
2. Inside Ubuntu, follow the official
   [Docker Engine installation instructions](https://docs.docker.com/engine/install/ubuntu/).
3. Verify the installation inside Ubuntu:

   ```sh
   sudo docker run hello-world
   ```

   Docker should print `Hello from Docker!`. After configuring non-root Docker
   access according to the official instructions, the exercise's exact command
   is `docker run hello-world`.
