{ pkgs }:

let
    heidisql-raw = pkgs.stdenv.mkDerivation rec {
        pname = "heidisql-raw";
        version = "12.17";
        
        src = pkgs.fetchurl {
            url = "https://github.com/HeidiSQL/HeidiSQL/releases/download/${version}/heidisql_${version}_amd64.deb";
            sha256 = "sha256-RCuJzyw+53OcUYfvodXHaZPy0w6Pxn3a2Wan06feTQw=";
        };

        qt6pas_deb = pkgs.fetchurl {
            url = "http://ftp.debian.org/debian/pool/main/libq/libqt6pas/libqt6pas6_2.4_amd64.deb";
            sha256 = "sha256-vKfT4Xie/hDrFAUMDI3bvk4k8QGx14JjgJRa1iG2M2w=";
        };

        nativeBuildInputs = [ pkgs.dpkg pkgs.autoPatchelfHook pkgs.qt6.wrapQtAppsHook ];
        
        buildInputs = [ 
            pkgs.qt6.qtbase pkgs.xorg.libX11 pkgs.glib 
            pkgs.mariadb-connector-c pkgs.postgresql.lib pkgs.sqlite
        ];

        dontWrapQtApps = true;

        unpackPhase = ''
            dpkg-deb -x $src .
            dpkg-deb -x ${qt6pas_deb} qt6pas_ext
        '';

        installPhase = ''
            mkdir -p $out/lib
            
            # Copy everything extracted from the deb's usr directory
            if [ -d usr ]; then
                cp -r usr/* $out/
            fi
            
            # Ensure lib exists and copy Pascal-Qt6 bindings
            find qt6pas_ext -name "libQt6Pas.so*" -exec cp {} $out/lib/ \;

            # Create library symlinks
            ln -s ${pkgs.mariadb-connector-c}/lib/mariadb/libmariadb.so.3 $out/lib/libmariadb.so
            ln -s ${pkgs.postgresql.lib}/lib/libpq.so.5 $out/lib/libpq.so
            ln -s ${pkgs.sqlite.out}/lib/libsqlite3.so.0 $out/lib/libsqlite3.so
            
            # Link them where the binary is (usually share/heidisql on Linux)
            if [ -d $out/share/heidisql ]; then
                ln -s $out/lib/libmariadb.so $out/share/heidisql/libmariadb.so
                ln -s $out/lib/libpq.so $out/share/heidisql/libpq.so
                ln -s $out/lib/libsqlite3.so $out/share/heidisql/libsqlite3.so
            fi
        '';
    };

    desktopItem = pkgs.makeDesktopItem {
        name = "heidisql";
        exec = "heidisql";
        icon = "heidisql";
        comment = "MySQL, MariaDB, PostgreSQL and SQLite manager";
        desktopName = "HeidiSQL";
        categories = [ "Development" "Database" ];
    };
in
pkgs.buildFHSEnv {
    name = "heidisql";
    targetPkgs = pkgs: with pkgs; [
        heidisql-raw
        mariadb-connector-c
        postgresql.lib
        sqlite
        openssl
        zlib
        glib
        freetype
        fontconfig
        libglvnd
        qt6.qtbase
        qt6.qtwayland
        xorg.libX11
        xorg.libXext
        xorg.libXrender
        icu
    ];

    extraInstallCommands = ''
        mkdir -p $out/share/applications
        cp ${desktopItem}/share/applications/* $out/share/applications/
        
        # Only copy icons if they actually exist in the raw build
        if [ -d ${heidisql-raw}/share/icons ]; then
        cp -r ${heidisql-raw}/share/icons $out/share/
        fi
    '';

    runScript = pkgs.writeScript "heidisql-wrapper" ''
        export LD_LIBRARY_PATH=/usr/lib/heidisql:/usr/lib:/usr/lib64:$LD_LIBRARY_PATH
        
        # Force Fusion style but tell it to use Dark Mode
        export QT_STYLE_OVERRIDE=fusion
        export QT_QPA_PLATFORMTHEME=""
        
        # Set the "Dark" flag for the underlying engine
        export GTK_THEME=Adwaita:dark
        export XDG_CURRENT_DESKTOP=GNOME
        
        # This is the key: Tell Qt to prefer a dark color palette 
        # and not use the system's broken inheritance.
        export QT_LOGGING_RULES="qt.qpa.gl=true"
        
        # Launch with the Fusion dark palette override
        # This ensures text is white and backgrounds are charcoal
        exec heidisql -style fusion "$@"
    '';

    multiPkgs = pkgs: [ pkgs.libGL ];
}