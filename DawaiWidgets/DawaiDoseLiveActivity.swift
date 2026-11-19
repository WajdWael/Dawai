//
//  DawaiDoseLiveActivity.swift
//  DawaiWidgets
//
//  Dynamic Island (iPhone 14 Pro / 15 and newer) and Lock Screen Live Activity for Dawai medication doses.
//

import ActivityKit
import WidgetKit
import SwiftUI

private extension Color {
    static let widgetDawaiPrimary = Color(red: 0.0 / 255.0, green: 123.0 / 255.0, blue: 120.0 / 255.0)
    static let widgetDawaiWarning = Color(red: 220.0 / 255.0, green: 95.0 / 255.0, blue: 30.0 / 255.0)
}

struct DawaiDoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DawaiDoseActivityAttributes.self) { context in
            // MARK: - Lock Screen / StandBy Banner
            lockScreenView(state: context.state)
                .widgetURL(context.state.confirmDoseURL)
                .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.92))
                .activitySystemActionForegroundColor(.widgetDawaiPrimary)
        } dynamicIsland: { context in
            let state = context.state
            let accentColor: Color = state.isLate ? .widgetDawaiWarning : .widgetDawaiPrimary

            return DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accentColor.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Image(systemName: state.isLate ? "exclamationmark.circle.fill" : "pills.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.medicationName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(state.dosage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(statusLabel(for: state))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor)
                            .clipShape(Capsule())

                        Text(state.timeString)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if state.isUpcoming && state.scheduledDate > Date() {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(accentColor)
                                Text("بعد")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                Text(timerInterval: Date()...state.scheduledDate, countsDown: true)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Link(destination: state.confirmDoseURL) {
                                Text("عرض الجدول")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(accentColor)
                                    .clipShape(Capsule())
                            }
                        } else {
                            Link(destination: state.confirmDoseURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("تأكيد أخذ الدواء")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(accentColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 4)
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                // MARK: - Compact Leading
                Image(systemName: state.isLate ? "exclamationmark.circle.fill" : "pills.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentColor)
            } compactTrailing: {
                // MARK: - Compact Trailing
                if state.isUpcoming && state.scheduledDate > Date() {
                    Text(timerInterval: Date()...state.scheduledDate, countsDown: true)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(maxWidth: 48)
                } else if state.isLate {
                    Text("متأخرة")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.widgetDawaiWarning)
                } else {
                    Text("الآن")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.widgetDawaiPrimary)
                }
            } minimal: {
                // MARK: - Minimal (when 2 activities are active)
                Image(systemName: state.isLate ? "exclamationmark.circle.fill" : "pills.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .widgetURL(state.confirmDoseURL)
            .keylineTint(accentColor)
        }
    }

    @ViewBuilder
    private func lockScreenView(state: DawaiDoseActivityAttributes.ContentState) -> some View {
        let accentColor: Color = state.isLate ? .widgetDawaiWarning : .widgetDawaiPrimary

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: state.isLate ? "exclamationmark.triangle.fill" : "pills.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.medicationName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(state.dosage) • \(state.timeString)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusLabel(for: state))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accentColor)
                        .clipShape(Capsule())

                    if state.isUpcoming && state.scheduledDate > Date() {
                        Text(timerInterval: Date()...state.scheduledDate, countsDown: true)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accentColor)
                    }
                }
            }

            if !state.isUpcoming {
                Link(destination: state.confirmDoseURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("تأكيد أخذ الدواء")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(14)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func statusLabel(for state: DawaiDoseActivityAttributes.ContentState) -> String {
        switch state.phase {
        case "late": return "جرعة متأخرة"
        case "due": return "حان الموعد"
        default: return "الجرعة القادمة"
        }
    }
}
