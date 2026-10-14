//
//  MedicationError.swift
//  Dawai
//
//  Use-Case 3 (UC-3): Add Medication
//  Validation and scheduling errors for medication entry and reminder configuration.
//

import Foundation

public enum MedicationError: LocalizedError, Equatable {
    case missingRequiredFields
    case invalidDosage
    case invalidTime
    case imageTooLarge
    case unsupportedImageFormat
    case imageAttachmentFailed
    case saveFailed
    case unauthorizedCaregiver
    case notificationSchedulingFailed

    public var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return "يرجى ملء جميع الحقول المطلوبة (اسم الدواء، الجرعة، ووقت الجرعة)."

        case .invalidDosage:
            return "الجرعة المدخلة غير صالحة. يرجى إدخال وصف صحيح للجرعة (مثال: حبة واحدة، 10 مل)."

        case .invalidTime:
            return "وقت غير صالح. يرجى اختيار وقت صحيح."

        case .imageTooLarge:
            return "حجم الصورة كبير جداً. الحد الأقصى المسموح به هو 5 ميجابايت."

        case .unsupportedImageFormat:
            return "صيغة الصورة غير مدعومة. يرجى اختيار صورة بصيغة JPG أو PNG أو HEIC."

        case .imageAttachmentFailed:
            return "تعذر إضافة الصورة. يرجى المحاولة مرة أخرى أو المتابعة بدون صورة."

        case .saveFailed:
            return "تعذر حفظ الدواء في الوقت الحالي. يرجى المحاولة مرة أخرى."

        case .unauthorizedCaregiver:
            return "لا تملك الصلاحية لإضافة دواء لهذا المستفيد. يرجى التحقق من اتصالك النشط وصلاحيات المتابعة."

        case .notificationSchedulingFailed:
            return "تم حفظ الدواء بنجاح، ولكن تعذر جدولة التنبيهات. يرجى التحقق من تفعيل أذونات الإشعارات في إعدادات الجهاز."
        }
    }
}
