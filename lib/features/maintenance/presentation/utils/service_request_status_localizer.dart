String getServiceRequestStatusArabic(String status) {
  switch (status) {
    case 'pending':
      return 'قيد الانتظار';
    case 'in_progress':
      return 'قيد التنفيذ';
    case 'completed':
      return 'مكتمل';
    case 'cancelled':
      return 'ملغي';
    default:
      return status;
  }
}
