package main

import "fmt"

// Student groups the information printed by the hello world program.
type Student struct {
	Name   string
	Course string
}

// Print introduces the student and prints every field of the struct.
// The value receiver is sufficient because this method does not change s.
func (s Student) Print() {
	fmt.Println("Hello, world!")
	fmt.Printf("Name: %s\n", s.Name)
	fmt.Printf("Course: %s\n", s.Course)
}

func main() {
	student := Student{
		Name:   "Daniel Sander Gassner",
		Course: "Software Architectures for Big Data",
	}
	student.Print()
}
