import SwiftUI

struct CourseListView: View {
    @ObservedObject var store: DataStore
    @State private var showingAddCourse = false
    @State private var newCourseName = ""
    @State private var selectedCourseForPlay: Course?
    @State private var selectedCourseForEdit: Course?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.courses) { course in
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text(course.name)
                                .font(.headline)
                            Text("\(course.holes.count) holes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                selectedCourseForPlay = course
                            }) {
                                Label("Play Round", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(course.holes.isEmpty)

                            Button(action: {
                                selectedCourseForEdit = course
                            }) {
                                Label("Edit Course", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .padding(.vertical, 8)
                }
                .onDelete { indexSet in
                    indexSet.forEach { store.deleteCourse(store.courses[$0]) }
                }
            }
            .listStyle(.plain)
            .navigationDestination(item: $selectedCourseForPlay) { course in
                HolePlayView(store: store, course: course)
            }
            .navigationDestination(item: $selectedCourseForEdit) { course in
                CourseEditorView(store: store, course: course)
            }
            .navigationTitle("My Courses")
            .toolbar {
                Button(action: { showingAddCourse = true }) {
                    Image(systemName: "plus")
                }
            }
            .alert("New Course", isPresented: $showingAddCourse) {
                TextField("Course name", text: $newCourseName)
                Button("Cancel", role: .cancel) { newCourseName = "" }
                Button("Add") {
                    if !newCourseName.isEmpty {
                        store.addCourse(name: newCourseName)
                        newCourseName = ""
                    }
                }
            }
            .alert("Error", isPresented: .constant(store.errorMessage != nil)) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}
