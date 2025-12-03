# GolfTracker

A GPS-powered golf tracking app for iOS and macOS that helps golfers map courses, track their shots in real-time, and analyze their game with precise distance measurements.

## Overview

GolfTracker combines course mapping with live GPS tracking to provide golfers with accurate distance information and detailed shot tracking. Whether you're playing a new course or analyzing your performance, GolfTracker gives you the data you need.

## Features

### Current Features
- **Course Management**: Create and manage custom golf courses
- **Interactive Course Mapping**: Use satellite imagery to precisely place hole positions by tapping on a map
- **Automatic Persistence**: All courses and holes are automatically saved locally
- **Course Library**: View all your saved courses with hole counts at a glance

### In Development
- **Real-Time Distance Tracking**: GPS-based distance calculation from your current location to each hole
- **Shot Tracking**: Record each shot with distance and location data
- **Live Round Play**: Play through a course hole-by-hole with live distance updates
- **Shot Distance Analysis**: Track how far each shot traveled

### Planned Features
- **Par Tracking**: Add par values to each hole for score analysis
- **Score Tracking**: Record scores for each hole and complete rounds
- **Round History**: View past rounds with statistics and performance trends
- **Editable Hole Positions**: Drag and reposition holes on the map
- **Course Routing Visualization**: See the course layout with lines connecting holes in order
- **Club Selection Tracking**: Record which club was used for each shot
- **Performance Analytics**: Charts and insights on driving distance, accuracy, and scoring trends

## Technical Details

### Architecture
- **SwiftUI**: Modern declarative UI framework
- **MapKit**: Satellite imagery and GPS coordinate handling
- **CoreLocation**: Precise GPS tracking for distance calculations
- **JSON Persistence**: Lightweight local data storage

### Data Models
- **Course**: Contains name and array of holes
- **Hole**: Stores hole number and GPS coordinates (latitude/longitude)
- **DataStore**: Observable object managing courses with automatic save/load

## Goals

The primary goal of GolfTracker is to leverage GPS technology to provide golfers with:
1. **Accurate Distance Information**: Know exactly how far you are from the hole at any moment
2. **Shot Performance Data**: Track shot distances to understand club performance
3. **Course Knowledge**: Build a personal database of courses you've played with precise hole locations
4. **Game Improvement**: Use data-driven insights to identify areas for improvement

## Getting Started

1. **Create a Course**: Tap the + button to add a new course
2. **Map the Holes**: Use the satellite map view to tap and place each hole position
3. **Play a Round**: (Coming soon) Start tracking your round with live GPS distances
4. **Analyze Your Game**: (Coming soon) Review shot distances and performance metrics

## Requirements

- iOS 17.0+ / macOS 14.0+
- Location permissions for GPS tracking
- Active GPS signal for distance tracking features
