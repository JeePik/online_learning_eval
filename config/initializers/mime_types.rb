Mime::Type.register "application/pdf", :pdf unless Mime::Type.lookup_by_extension(:pdf)
Mime::Type.register "text/csv", :csv unless Mime::Type.lookup_by_extension(:csv)
