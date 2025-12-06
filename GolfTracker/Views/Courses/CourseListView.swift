import SwiftUI

struct CourseListView: View {
    @ObservedObject var store: DataStore
    @State private var showingAddCourse = false
    @State private var newCourseName = ""
    @State private var selectedCourse: Course?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.courses) { course in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if let city = course.city {
                                Text(city)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCourse = course
                    }
                    .onAppear {
                        if course.city == nil && !course.holes.isEmpty {
                            store.updateCourseCity(course)
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { store.deleteCourse(store.courses[$0]) }
                }
            }
            .listStyle(.plain)
            .navigationDestination(item: $selectedCourse) { course in
                CourseDetailView(store: store, course: course)
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
