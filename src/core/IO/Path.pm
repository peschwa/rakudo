my class IO::Path is Cool does IO::FileTestable {
    has IO::Spec $.SPEC;
    has Str $.CWD;
    has Str $.path;
    has Bool $.is-absolute;
    has Str $!abspath;  # should be native for faster file tests, but segfaults
    has %!parts;

    multi method ACCEPTS(IO::Path:D: IO::Path:D \other) {
        nqp::p6bool(nqp::iseq_s($!path, nqp::unbox_s(other.path)));
    }

    multi method ACCEPTS(IO::Path:D: Mu \that) {
        nqp::p6bool(nqp::iseq_s($!path,nqp::unbox_s(IO::Path.new(|that).path)));
    }

    submethod BUILD(:$!path! as Str, :$!SPEC!, :$!CWD! as Str) { }

    multi method new(IO::Path: $path, :$SPEC = $*SPEC, :$CWD = $*CWD) {
        self.bless(:$path, :$SPEC, :$CWD);
    }
    multi method new(IO::Path:
      :$basename!,
      :$dirname = '.',
      :$volume  = '',
      :$SPEC    = $*SPEC,
      :$CWD     = $*CWD,
    ) {
        self.bless(:path($SPEC.join($volume,$dirname,$basename)),:$SPEC,:$CWD);
    }
    multi method new(IO::Path:
      :$basename,
      :$directory!,
      :$volume = '',
      :$SPEC   = $*SPEC,
      :$CWD    = $*CWD,
    ) {
#        DEPRECATED(':dirname', :what<IO::Path.new with :directory>); # after 2014.10
        self.bless(
          :path($SPEC.join($volume,$directory,$basename)), :$SPEC, :$CWD);
    }

    method abspath() {
        $!abspath //= $!path.substr(0,1) eq '-'
          ?? ''
          !! $!SPEC.rel2abs($!path,$!CWD);
    }
    method is-absolute() {
        $!is-absolute //= $!SPEC.is-absolute($!path);
    }
    method is-relative() {
        !( $!is-absolute //= $!SPEC.is-absolute($!path) );
    }

    method parts                  {
        %!parts ||= $!SPEC.split($!path);
    }
    method volume(IO::Path:D:)   { %.parts<volume>   }
    method dirname(IO::Path:D:)  { %.parts<dirname>  }
    method basename(IO::Path:D:) { %.parts<basename> }

    # core can't do 'basename handles <Numeric Bridge Int>'
    method Numeric(IO::Path:D:) { self.basename.Numeric }
    method Bridge (IO::Path:D:) { self.basename.Bridge  }
    method Int    (IO::Path:D:) { self.basename.Int     }

    multi method Str (IO::Path:D:) { $!path }
    multi method gist(IO::Path:D:) {
        "q|$.abspath|.IO";
    }
    multi method perl(IO::Path:D:) {
        ($.is-absolute
          ?? "q|$.abspath|.IO(:SPEC({$!SPEC.^name}))"
          !! "q|$.path|.IO(:SPEC({$!SPEC.^name}),:CWD<$!CWD>)"
        ).subst(:global, '\\', '\\\\');
    }

    method succ(IO::Path:D:) {
        self.bless(
          :path($!SPEC.join($.volume,$.dirname,$.basename.succ)),
          :$!SPEC,
          :$!CWD,
        );
    }
    method pred(IO::Path:D:) {
        self.bless(
          :path($!SPEC.join($.volume,$.dirname,$.basename.pred)),
          :$!SPEC,
          :$!CWD,
        );
    }

    method IO(IO::Path:D: |c) {
        $?CLASS.new($!path, :$!SPEC, :$!CWD, |c);
    }

    method open(IO::Path:D: |c) {
        my $handle = IO::Handle.new(:path($.abspath));
        $handle && $handle.open(|c);
    }

#?if moar
    method watch(IO::Path:D:) {
        IO::Notification.watch_path($.abspath);
    }
#?endif

    proto method absolute(|) { * }
    multi method absolute (IO::Path:D:) { $.abspath }
    multi method absolute (IO::Path:D: $CWD) {
        self.is-absolute
          ?? $.abspath
          !! $!SPEC.rel2abs($!path, $CWD);
    }

    method relative (IO::Path:D: $CWD = $*CWD) {
        $!SPEC.abs2rel($.abspath, $CWD);
    }

    method cleanup (IO::Path:D:) {
        self.bless(:path($!SPEC.canonpath($!path)), :$!SPEC, :$!CWD);
    }
    method resolve (IO::Path:D:) {
        # NYI: requires readlink()
        X::NYI.new(feature=>'IO::Path.resolve').fail;
    }

    method parent(IO::Path:D:) {    # XXX needs work
        my $curdir := $!SPEC.curdir;
        my $updir  := $!SPEC.updir;

        if self.is-absolute {
            return self.bless(
              :path($!SPEC.join($.volume, $.dirname, '')),
              :$!SPEC,
              :$!CWD,
            );
        }
        elsif $.dirname eq $curdir and $.basename eq $curdir {
            return self.bless(
              :path($!SPEC.join($.volume,$curdir,$updir)),
              :$!SPEC,
              :$!CWD,
            );
        }
        elsif $.dirname eq $curdir && $.basename eq $updir
           or !grep({$_ ne $updir}, $!SPEC.splitdir($.dirname)) {
            return self.bless(    # If all updirs, then add one more
              :path($!SPEC.join($.volume,$!SPEC.catdir($.dirname,$updir),$.basename)),
              :$!SPEC,
              :$!CWD,
            );
        }
        else {
            return self.bless(
              :path($!SPEC.join($.volume, $.dirname, '')),
              :$!SPEC,
              :$!CWD,
            );
        }
    }

    method child (IO::Path:D: $child) {
        self.bless(:path($!SPEC.catfile($!path,$child)), :$!SPEC, :$!CWD);
    }

    proto method rename(|) { * }
    multi method rename(IO::Path:D: IO::Path:D $to, :$createonly) {
        if $createonly and $to.e {
            fail X::IO::Rename.new(
              :from($.abspath),
              :$to,
              :os-error(':createonly specified and destination exists'),
            );
        }
        nqp::rename($.abspath, nqp::unbox_s($to.abspath));
        CATCH { default {
            fail X::IO::Rename.new(
              :from($!abspath), :$to($to.abspath), :os-error(.Str) );
        } }
        True;
    }
    multi method rename(IO::Path:D: $to, :$CWD = $*CWD, |c) {
        self.rename($to.IO(:$!SPEC,:$CWD),|c);
    }

    proto method copy(|) { * }
    multi method copy(IO::Path:D: IO::Path:D $to, :$createonly) {
        if $createonly and $to.e {
            fail X::IO::Copy.new(
              :from($.abspath),
              :$to,
              :os-error(':createonly specified and destination exists'),
            );
        }
        nqp::copy($.abspath, nqp::unbox_s($to.abspath));
        CATCH { default {
            fail X::IO::Copy.new(
              :from($!abspath), :$to, :os-error(.Str) );
        } }
        True;
    }
    multi method copy(IO::Path:D: $to, :$CWD  = $*CWD, |c) {
        self.copy($to.IO(:$!SPEC,:$CWD),|c);
    }

    method chmod(IO::Path:D: $mode as Int) {
        nqp::chmod($.abspath, nqp::unbox_i($mode));
        CATCH { default {
            fail X::IO::Chmod.new(
              :path($!abspath), :$mode, :os-error(.Str) );
        } }
        True;
    }
    method unlink(IO::Path:D:) {
        nqp::unlink($.abspath);
        CATCH { default {
            fail X::IO::Unlink.new( :path($!abspath), os-error => .Str );
        } }
        True;
    }

    method symlink(IO::Path:D: $name is copy, :$CWD  = $*CWD) {
        $name = $name.IO(:$!SPEC,:$CWD).path;
        nqp::symlink(nqp::unbox_s($name), $.abspath);
        CATCH { default {
            fail X::IO::Symlink.new(:target($!abspath), :$name, os-error => .Str);
        } }
        True;
    }

    method link(IO::Path:D: $name is copy, :$CWD  = $*CWD) {
        $name = $name.IO(:$!SPEC,:$CWD).path;
        nqp::link(nqp::unbox_s($name), $.abspath);
        CATCH { default {
            fail X::IO::Link.new(:target($!abspath), :$name, os-error => .Str);
        } }
        True;
    }

    method mkdir(IO::Path:D: $mode = 0o777) {
        nqp::mkdir($.abspath, $mode);
        CATCH { default {
            fail X::IO::Mkdir.new(:path($!abspath), :$mode, os-error => .Str);
        } }
        True;
    }

    method rmdir(IO::Path:D:) {
        nqp::rmdir($.abspath);
        CATCH { default {
            fail X::IO::Rmdir.new(:path($!abspath), os-error => .Str);
        } }
        True;
    }

    method contents(IO::Path:D: |c) {
#        DEPRECATED('dir');   # after 2014.10
        self.dir(|c);
    }

    method dir(IO::Path:D:   # XXX needs looking at
        Mu :$test = $*SPEC.curupdir,
        :$absolute,
        :$CWD = $*CWD,
    ) {

        CATCH { default {
            fail X::IO::Dir.new(
              :path(nqp::box_s($.abspath,Str)), :os-error(.Str) );
        } }
        my $cwd_chars = $CWD.chars;

#?if !jvm
        my str $cwd = nqp::cwd();
        nqp::chdir(nqp::unbox_s($.abspath));
#?endif

#?if parrot
        my Mu $RSA := pir::new__PS('OS').readdir($!abspath);
        my int $elems = nqp::elems($RSA);
        gather {
            loop (my int $i = 0; $i < $elems; $i = $i + 1) {
                my Str $file := nqp::p6box_s(pir::trans_encoding__Ssi(
                  nqp::atpos_s($RSA, $i),
                  pir::find_encoding__Is('utf8')));
                if $file ~~ $test {
                    take self.child($file);   # XXX needs looking at
                }
            }
            nqp::chdir($cwd);
        }
#?endif
#?if !parrot

        my Mu $dirh := nqp::opendir(nqp::unbox_s($.abspath));
        my $next = 1;
        gather {
            take $_.IO(:$!SPEC,:$*CWD) if $_ ~~ $test for ".", "..";
            loop {
                my str $elem = nqp::nextfiledir($dirh);
                if nqp::isnull_s($elem) || nqp::chars($elem) == 0 {
                    nqp::closedir($dirh);
                    last;
                }
                elsif $elem ne '.' | '..' {
#?endif
#?if moar
                    $elem = $!SPEC.catfile($!abspath, $elem); # moar = relative
                    $elem = nqp::substr($elem, $cwd_chars + 1) if !$absolute;
                    take $elem.IO(:$!SPEC,:$CWD) if $test.ACCEPTS($elem);
                }
            }
            nqp::chdir($cwd);
        }
#?endif
#?if jvm
                    $elem = nqp::substr($elem, $cwd_chars + 1) if !$absolute;
                    take $elem.IO(:$!SPEC,:$CWD) if $test.ACCEPTS($elem);
                }
            }
        }
#?endif
    }

    proto method slurp() { * }
    multi method slurp(IO::Path:D: |c) {
        my $handle = self.open(|c);
        $handle && do {
            my $slurp := $handle.slurp(|c);
            $handle.close;  # can't use LEAVE in settings :-(
            $slurp;
        }
    }

    proto method spurt(|) { * }
    multi method spurt(IO::Path:D: $what, :$enc = 'utf8', :$append, :$createonly, |c) {
        if $createonly and self.e {
            fail("File '$!path' already exists, and :createonly was specified");
        }
        my $mode = $append ?? :a !! :w;
        my $handle = self.open(:$enc, |$mode, |c);
        $handle && do {
            my $spurt := $handle.spurt($what, :$enc, |c);
            $handle.close;  # can't use LEAVE in settings :-(
            $spurt;
        }
    }

    proto method lines() { * }
    multi method lines(IO::Path:D: |c) {
        my $handle = self.open(|c);
        $handle && $handle.lines(:close, |c);
    }

    proto method words() { * }
    multi method words(IO::Path:D: |c) {
        my $handle = self.open(|c);
        $handle && $handle.words(:close, |c);
    }

    method directory() {
#        DEPRECATED("dirname");   # after 2014.10
        self.dirname;
    }
}

my class IO::Path::Cygwin is IO::Path {
    method new(|c) { IO::Path.new(|c, :SPEC(IO::Spec::Cygwin) ) }
}
my class IO::Path::QNX is IO::Path {
    method new(|c) { IO::Path.new(|c, :SPEC(IO::Spec::QNX) ) }
}
my class IO::Path::Unix is IO::Path {
    method new(|c) { IO::Path.new(|c, :SPEC(IO::Spec::Unix) ) }
}
my class IO::Path::Win32 is IO::Path {
    method new(|c) { IO::Path.new(|c, :SPEC(IO::Spec::Win32) ) }
}

# vim: ft=perl6 expandtab sw=4
