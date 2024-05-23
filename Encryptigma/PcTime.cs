using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Encryptigma
{
    public class PcTime
    {
        public string GetFormattedTime()
        {
            DateTime nowTime = DateTime.Now;
            string formattedTime = nowTime.ToString("HHmm");
            return formattedTime;
        }
    }
}
