{
  pkgs,
  lib,
  nfx,
  api,
  fileList,
}:
let
  githubBase = "https://github.com/vic/nfx/blob/main";

  # Helper to extract documentation from mk results
  extractDocs =
    v:
    if builtins.isAttrs v && v ? doc && v ? value then
      # This is an mk result
      {
        doc = v.doc;
        combinators = if builtins.isAttrs v.value then lib.mapAttrs (_: extractDocs) v.value else { };
      }
    else if builtins.isAttrs v then
      # Recurse into plain attrset
      lib.mapAttrs (_: extractDocs) v
    else
      {
        doc = "";
        combinators = { };
      };

  # Extract docs from a file
  extractFileDoc =
    file:
    let
      # Create context with full nfx
      ctx = {
        inherit lib api nfx;
        config.nfx.lib = nfx;
      };
      mkResult = import file ctx;
    in
    extractDocs mkResult;

  # Generate markdown for a module
  generateModuleMd =
    name: namespace: path:
    let
      docs = extractFileDoc path;
      githubUrl = "${githubBase}/${builtins.toString path}";
      namespacePrefix = if namespace != null then "${namespace}." else "";

      moduleHeader = ''
        # ${name}

        > **Source:** [${builtins.toString path}](${githubUrl})
        > ${lib.optionalString (namespace != null) "\n**Namespace:** `${namespace}`\n"}

        ***Module Description***

        ${docs.doc}

        ## Combinators

      '';

      combinatorSection = lib.concatStringsSep "\n\n" (
        lib.mapAttrsToList (combName: combData: ''
          ### `${namespacePrefix}${combName}`

          ${lib.replaceStrings [ "## " "### " ] [ "#### " "##### " ] combData.doc}
        '') (lib.filterAttrs (_: v: v ? doc && v.doc != "") docs.combinators)
      );

      footer = ''

        ---

        _Generated from [${builtins.toString path}](${githubUrl})_
      '';
    in
    moduleHeader + combinatorSection + footer;

  # Process all files from fileList
  allModuleDocs = lib.foldl' (
    acc: file:
    let
      # Handle both single path and multiple paths (for stream)
      filesToProcess = if file ? paths then file.paths else [ file.path ];

      # Generate docs for each file
      fileDocs = map (p: {
        name = "${file.name}${if file ? paths then "-${baseNameOf (toString p)}" else ""}";
        namespace = file.namespace or null;
        path = p;
      }) filesToProcess;
    in
    acc ++ fileDocs
  ) [ ] fileList;

  # Create individual markdown files
  mdFiles = lib.listToAttrs (
    map (file: {
      name = file.name;
      value = generateModuleMd file.name file.namespace file.path;
    }) allModuleDocs
  );

  # Create mdbook summary
  summaryMd = ''
    ${lib.concatMapStringsSep "\n" (file: "- [${file.name}](${file.name}.md)") allModuleDocs}
  '';

in
pkgs.runCommand "nfx-docs"
  {
    passAsFile = [ "summaryMd" ] ++ (lib.mapAttrsToList (n: _: n) mdFiles);
    summaryMd = summaryMd;
  }
  (
    lib.concatStringsSep "\n" (
      [
        "mkdir -p $out"
        "cp $summaryMdPath $out/SUMMARY.md"
      ]
      ++ (lib.mapAttrsToList (name: content: ''
        cat > $out/${name}.md <<'EOFDOC'
        ${content}
        EOFDOC
      '') mdFiles)
    )
  )
