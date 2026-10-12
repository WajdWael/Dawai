//
//  InvitationError.swift
//  Dawai
//
//  Use-Case 2 (UC-2): Link Patient and Caregiver
//  Validation errors for invitation processing and role compatibility.
//

import Foundation

public enum InvitationError: LocalizedError, Equatable {
    case tokenNotFound
    case tokenExpired
    case incompatibleRoles(initiatorRole: UserRole, recipientRole: UserRole)
    case selfInvitation
    case relationshipAlreadyExists
    case invitationNotAcceptedYet
    case invitationAlreadyProcessed

    public var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            return "رمز الدعوة غير صالح أو غير موجود."
            
        case .tokenExpired:
            return "انتهت صلاحية رابط الدعوة (صالحة لمدة 48 ساعة فقط). يرجى طلب رابط جديد."
            
        case .incompatibleRoles(let initiatorRole, _):
            if initiatorRole == .patient {
                return "الأدوار غير متوافقة: مرسل الدعوة مستفيد، ولا يمكن ربط مستفيد بمستفيد آخر. يجب أن يكون الطرف الآخر مقدم رعاية."
            } else {
                return "الأدوار غير متوافقة: مرسل الدعوة مقدم رعاية، ولا يمكن ربط مقدم رعاية بمقدم رعاية آخر. يجب أن يكون الطرف الآخر مستفيداً."
            }
            
        case .selfInvitation:
            return "لا يمكنك قبول دعوة مرسلة من قبلك."
            
        case .relationshipAlreadyExists:
            return "توجد بالفعل علاقة ربط نشطة بينكما."
            
        case .invitationNotAcceptedYet:
            return "لم يقم الطرف الآخر بقبول الدعوة بعد حتى تتمكن من تأكيدها."
            
        case .invitationAlreadyProcessed:
            return "تمت معالجة هذه الدعوة مسبقاً."
        }
    }
}
