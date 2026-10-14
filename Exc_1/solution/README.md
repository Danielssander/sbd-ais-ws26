# Exercise 1 - Solution

## Run the program

To run my program, open a terminal in the repository folder and use:

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

The program needs Go 1.22 or newer. It only uses the standard library, so no
extra packages are needed.

## Validation

The program was checked with Go 1.27.2 on Windows:

- Formatted with `gofmt`.
- `go vet .` passed.
- `go run .` produced the output above.
- `go build` succeeded and the compiled program produced the same output.

The installed swaggo module is v1.16.6; its CLI reports v1.16.4.

## How it works

I used a `Student` struct with two string fields: `Name` and `Course`.
In `main`, I create a student with my name and the name of the course.

The method `func (s Student) Print()` has a receiver of type `Student`.
When I call `student.Print()`, it prints "Hello, world!" followed by the
values of both fields. I used a value receiver because the method only reads
the data. It works with a copy of the struct and does not change the original.

## Go Tour study notes

The reading for this exercise goes from [the basics](https://go.dev/tour/basics/1)
to [methods and interfaces, page 20](https://go.dev/tour/methods/20).
These are some of the main points to remember:

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

I already have a GitHub account and forked `ddibiasi/sbd-ais-ws26`.
I also have Visual Studio Code installed on my Windows computer.

For now, Go and swaggo are installed in a local folder for running and
checking the program. They have not been added to my system PATH yet.
To finish the regular setup, I still need to install Go from
[go.dev](https://go.dev/dl/) and make the swaggo CLI available with:

```sh
go install github.com/swaggo/swag/cmd/swag@v1.16.6
```

After adding Go's `bin` folder and `$(go env GOPATH)/bin` to PATH, I can check
the installation with:

```sh
go version
swag --version
```

Swaggo will be needed for the API exercises later on. I do not need to
generate Swagger documentation for this hello world program.
