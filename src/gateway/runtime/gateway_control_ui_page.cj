package metis.gateway.runtime

public func gatewayBuildControlUiPageHtml(title: String, headExtra: String, bodyHtml: String, scriptBody: String): String {
    """
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>${title}</title>
${headExtra}
</head>
<body>
${bodyHtml}
  <script>
${scriptBody}
  </script>
</body>
</html>
"""
}
